-- OPTYMALIZACJA: +=/-=/*= to skroty PICO-8; split tworzy liste liczb.
-- TAPTAP: ruch, machniecia i szybowanie
-- Komentarze bez polskich znakow dla zgodnosci z edytorem PICO-8.
-- Gra uzywa _update: 30 klatek na sekunde (6 klatek = 0.2 s).
-- Pozycje: piksele. Predkosci: piksele/klatke.
-- Przyspieszenia: zmiana predkosci w kazdej klatce.
-- Os Y rosnie w dol: ujemne p_vy = wznoszenie.
--
-- SZYBKIE STROJENIE:
-- dash_speed / short_lift: krotki tap, poziomo / pionowo.
-- hold_drift / flap_speed: przycisk X, poziomo / pionowo.
-- Machniecie na nacisnieciu ustawia wektor, bez premii za chodzenie.
-- Strzalki koryguja tylko opadanie, bez zawracania; sciana wymaga kierunku do niej.
-- wiatr w pokoju: podpisana predkosc px/klatke; minus lewo, plus prawo.

--
-- 1. START I PARAMETRY DO STROJENIA
--
function _init()
 t=0
 -- SFX 63 zarezerwowany na szelest skrzydel; tworzony w RAM, bez edycji .p8.
 flap_sfx=63
 local address=0x3200+flap_sfx*68
 memset(address,0,68)
 poke(address+65,2)
 for i=0,3 do poke2(address+i*2,2472-i*516) end
 -- ID pierwszej klatki w taptap.p8; kazda animacja ma 4 kolejne klatki.
 p_anims={
  idle=96, -- stanie na platformie
  walk=112, -- chodzenie i wyhamowywanie
  fly=80, -- pojedyncze machniecie
  glide=64 -- szybowanie po machnieciu
 }

 -- KOT: patrol, ostrzezenie, atak i powrot do punktu odrodzenia pokoju.
 -- Kot w pokoju ma lokalny timer od wejscia gracza; bez podrozy przez inne pokoje.
 -- cat_room: aktualny pokoj kota; nil podczas podrozy
 -- cat_entry_side: -1: lewa krawedz, 1: prawa; 0: start/podroz pionowa
 -- cat_entry_x: pozycja pozioma przy przejsciu pionowym
 -- cat_travel: odliczanie do wejscia, w klatkach
 cat_room,cat_destination,cat_entry_side,cat_entry_x,cat_travel,cat_started=nil,nil,0,60,0,false
 cat_spawn_checked=nil -- nie szukamy podlogi co klatke
 cat_walk=116
 cat_idle=100
 cat_crouch=84
 cat_carry=68
 cat_jump_anim=120
 -- cat_jump_height: maksymalna roznica wysokosci platform, 2 tile
 -- cat_jump_reach: maksymalny zasieg poziomy
 -- cat_jump_ticks: maksymalny czas skoku; nizszy/blizszy cel = krocej
 -- cat_jump_clearance: zapas nad platforma, w px
 -- cat_gravity: wspolna grawitacja: poscig, zeskok i niesienie ptaszka
 -- cat_pounce_speed: maksymalny impuls; rzeczywisty zalezy od wysokosci celu
 -- cat_jump_retry: nie szukaj nowego skoku co klatke
 cat_jump_height,cat_jump_reach,cat_jump_ticks,cat_jump_clearance,cat_gravity,cat_fall_speed,cat_pounce_speed,cat_jump_retry=unpack(split("16,24,24,1,0.12,2.4,2.0,30"))
 -- cat_seek_reach: maksymalne boczne podejscie pod krawedz platformy
 -- cat_seek_ticks: planowanie podejscia najwyzej raz na sekunde
 cat_seek_reach,cat_seek_ticks=40,30
 feather_anim=124
 -- Znajdzki wypelniane z ustawien pokojow ponizej.
 feather_defs={}
 feathers_collected={} -- trwałe ID po wyjsciu z pokoju
 feathers_pending={} -- dotkniete w tym pokoju, jeszcze niezapisane
 -- cat_crouch_ticks: ostrzezenie przed atakiem, ok. 0.67 s
 -- cat_attack_ticks: krotki wypad, kierunek ustalony przed przykucem
 -- cat_attack_range: odleglosc pozioma wyzwalajaca przykuc
 -- cat_attack_height: kot nie atakuje ptaszka wysoko nad glowa
 -- cat_attack_cooldown: oddech po chybieniu, 1.5 s
 -- capture_run_ticks: 2 s ucieczki ze zmniejszaniem kola
 -- capture_black_ticks: 0.5 s czerni przed powrotem
 cat_crouch_ticks,cat_attack_ticks,cat_attack_speed,cat_attack_range,cat_attack_height,cat_attack_cooldown,capture_run_ticks,capture_black_ticks=unpack(split("20,12,1.21,22,10,45,60,15"))
 -- capture: osobna scena; nie aktualizuje czasu ani fizyki swiata
 -- p_safe_ticks: ochrona po powrocie
 -- cat_stop_margin: zatrzymaj poscig w tej odleglosci poziomej (px)
 -- cat_resume_margin: rusz ponownie dopiero po oddaleniu ptaszka (px)
 capture,p_safe_ticks,cat_walk_speed,cat_chase_speed,cat_anim_ticks,cat_stop_margin,cat_resume_margin=nil,0,0.242,0.44,8,10,18
 -- cat_react_ticks: decyzja o kierunku co ~0.27 s, nie co piksel
 -- cat_notice_ticks: pamiec celu przez 1.5 s poza widokiem
 cat_react_ticks,cat_notice_ticks,cat=10,45,nil

 -- CHODZENIE: polowa poprzedniej predkosci, bez premii do lotu.
 move_acc,acc_growth,ramp_ticks=0.04,0.0002,60
 ground_max_speed,ground_brake,ground_drag=0.4125,0.14,0.927
 air_drag=0.99 -- rozped lotu zanika powoli, niezaleznie od chodzenia
 air_correction=0.2 -- tylko opadanie: +/-20%, bez zawracania

 -- HITBOX: 4x5 px wewnatrz spritea 8x8; prawa/dolna krawedz sa wylaczne.
 -- wall_slide_speed: lagodne zsuwanie po scianie typu 1
 -- ground_refill_ticks: odnowa na ziemi i przy scianie: ok. 0.67 s
 -- flap_refill_pause_ticks: pauza odnowy po machnieciu: 0.5 s przy 30 fps
 hit_left,hit_right,hit_top,hit_bottom,wall_slide_speed,ground_refill_ticks,flap_refill_pause_ticks=unpack(split("2,6,2,7,0.22,20,15"))
 -- wall_steer_ticks: ochrona przed wiatrem przez pierwsze klatki odbicia
 wall_steer_ticks=10

 -- GRAWITACJA I OPADANIE
 -- gravity: wyhamowanie wznoszenia; opadanie ma osobne, lagodne parametry
 -- glide_gravity: narastanie opadania po osiagnieciu szczytu lotu
 -- fall_speed: staly limit szybowania niezalezny od strzalek, w px/klatke
 gravity,glide_gravity,fall_speed=unpack(split("0.088,0.036,0.68"))

 -- WEKTORY LOTU (px/klatke). O/Z = dash, X = wznoszenie.
 -- Kazde machniecie ustawia predkosc: X wyhamowuje poprzedni dash.
 dash_speed,hold_drift,short_lift,flap_speed=1.079568,0.36,0.5544,1.8648
 bumper_speed,bumper_lift=1.62,0.83 -- bok: predkosc i lekkie podbicie
 bumper_up=2.1 -- trafienie trampoliny od gory: mocne wybicie pionowe
 max_rise_speed=2.2

 -- Jedno nacisniecie = jedna animacja i jedno zuzyte piorko.
 max_flaps=2 -- maksymalny zapas; ladowanie poza lodem odnawia jedno

 -- WSPOLNY WIDOK DLA WSZYSTKICH POKOI.
 vision_radius=44 -- promien px; 0 wylacza ciemnosc
 vision_breathe=2 -- pulsowanie +/- px; 0 = staly promien
 vision_period=120 -- klatki na cykl; 120 = 4 sekundy
 vision_fade=6 -- szerokosc gradientu px
 vision_room=nil -- bufor przyciemnionych kafelkow

 -- ANIMACJA I MAPA
 wing_frame_ticks=2 -- szybszy, czytelniejszy ruch skrzydel na kazde tapniecie
 wing_duration=wing_frame_ticks*4 -- jeden cykl 8 klatek (ok. 0.27 s)

 -- KOLIZJE PO NUMERZE SPRITEA: nie trzeba ustawiac flag w edytorze.
 -- Wpisz ID spriteow miedzy klamrami, np. {3,4}.
 -- Te platformy przepuszczaja od dolu i bokow, ale mozna na nich stac.
 -- Lista ponizej: przelot od dolu i bokow, ladowanie od gory.
 one_way_tiles=split("1,16,17,32,33,48,49")


 -- LOD: pelna kolizja, brak regeneracji i zaczepienia na boku.
 -- Kolumny 8..10, wiersze 0..3: lod. Kolumny 11..12: ogien.
 -- 13: druga klatka trampoliny 14; 29,45,61: tlo bez kolizji.
 fire_drain_ticks=30 -- jedno dostepne machniecie za sekunde kontaktu z lawa
 -- ice_ground_drag: wiecej poslizgu po puszczeniu kierunku
 -- ice_ground_brake: slabsze hamowanie przy zmianie kierunku
 ice_ground_drag,ice_ground_brake=0.985,0.055

 -- SCIANY PO ID SPRITEA: nie trzeba ustawiac flag.
 -- 0 = brak zaczepienia; 1 i 2 = wolny slizg, bez zatrzymania opadania.
 -- Te wpisy nadaja tez pelna kolizje. Platformy one_way maja pierwszenstwo.
 -- Edytuj ID po lewej, typ po prawej. Np. [17]=2 to przyczepny sprite 17.
 -- Kolumny 2..7, cztery wiersze (+16): zwykle pelne bloki.
 -- Wszystkie przyczepne sciany zsuwaja ptaszka z wall_slide_speed.
 wall_tile_types={}
 for row=0,3 do
  for col=2,12 do
   local kind=1
   if col==5 or col==6 then kind=2 end
   if col>=8 then kind=0 end
   wall_tile_types[col+row*16]=kind
  end
 end
 -- Pozostale pelne bloki zachowuja wolny slizg.
 -- Sciana laduje kolejne machniecia, w tempie jak na ziemi.

 -- BLOKI WIDOCZNE PRZEZ CIEMNA MGLE (numery spriteow, bez flag).
 -- Przyklad: fog_visible_tiles={3,4} pokazuje te grafiki nawet za sciana
 -- i poza promieniem. Lista dotyczy wszystkich ich wystapien na mapie.
 -- Pusta lista = brak wyjatkow. Nie zmienia kolizji ani rzucanych cieni.
 -- Po zmianie listy/terenu podczas gry ustaw vision_room=nil.
 fog_visible_tiles=split("2,3,18,19,34,35,50,51,54")
 -- Kolor oryginalny 0..15 -> przyciemniony kolor (indeks = kolor+1).
 -- Czarne piksele spritea pozostaja przezroczyste jak przy map().
 fog_dim_colors=split("0,1,1,1,2,1,5,6,2,4,9,3,1,1,2,5")
 -- Przyklad: one_way_tiles={2} zmieni WSZYSTKIE kafelki 2 w platformy.
 -- Dla osobnej platformy skopiuj grafike bloku do wolnego spritea
 -- i wpisz tutaj jego numer. Uzyj tego spritea na mapie.

 -- SWIAT JEST DOKLADNIE TAK ULOZONY JAK MAPA W EDYTORZE.
 -- Pokoj (room_x,room_y) ma zrodlo map(room_x*16,room_y*16,...).
 -- Wspolrzedne pokojow liczymy OD ZERA, kazdy ma 16x16 kafelkow.
 -- Osma kolumna (x=112..127) jest zarezerwowana na ekrany menu.
 -- Mapa y=32..63 dzieli pamiec ze spriteami 128..255: rezerwujemy je na teren.
 -- Animacje sa teraz w spriteach 64..127, poza wspoldzielona pamiecia.
 -- Swiat: 7x4 pokoje, kafelki mapy x=0..111, y=0..63.
 room_cols,room_rows=7,4
 -- Numery pokojow, od lewej do prawej:
 --  1  2  3  4  5  6  7
 --  8  9 10 11 12 13 14
 -- 15 16 17 18 19 20 21
 -- 22 23 24 25 26 27 28
 start_room_id=8
 start_position="15,18" --"17,33" --"1,41" -- GLOBALNE kafelki: osobny punkt pierwszego startu
 -- ID sluzy tylko ustawieniom/odwiedzinom, NIE przestawia grafiki pokojow.
 -- ID=1+room_y*room_cols+room_x. Puste fragmenty mapy to puste pokoje.
 -- USTAWIENIA POKOJOW: jeden wiersz = jeden pokoj (numer przed pierwszym |).
 -- Zmieniaj tylko dane w bloku [[...]], zachowaj nazwy i separatory.
 -- kot=min,max: sekundy oczekiwania; 0,0 = brak kota.
 -- kot_lata=1: latajacy; 0: naziemny. Typ jest osobny dla kazdego pokoju.
 -- kot_spawn=x,y: GLOBALNE kafelki, lewy gorny rog kota (tak jak reset).
 -- Latajacy wymaga punktu. Naziemny: - zachowuje automatyczne wejscie.
 -- Punkt musi byc wolny; naziemny wymaga podlogi pod stopami.
 -- Zly punkt nie teleportuje kota gdzie indziej: popraw go w danych pokoju.
 -- reset i piorko: GLOBALNE kafelki edytora, od zera (x=0..111, y=0..63).
 -- 1 kafelek = 8 px; 0.125 kafelka = 1 px. Pozycja lewego gornego rogu spritea.
 -- Punkty musza lezec w pokoju podanym na poczatku wiersza.
 -- reset=x,y: 1..4 punkty rozdzielone srednikiem, 
 --lewa;prawa;gora;dol.
 -- Kolejnosc: LEWA;PRAWA;GORA;DOL. Brak wariantu = pierwszy punkt.
 -- Domyslnie okolice srodkow krawedzi, pelne kafelki, odsuniecie 8 px.
 -- Dostosuj punkt, jesli w tym miejscu narysujesz teren lub kolce.
 -- piorko=- oznacza brak; piorko=x,y oznacza jedna znajdzke. ID = numer pokoju.
 -- wiatr: staly dryf w locie, -0.12 = lewo, 0 = cisza, 0.12 = prawo.
 -- Bezpieczny zakres testowy -0.12..0.12; nie dotyczy chodzenia ani kota.
 -- Widocznosc jest globalna; tarcie zalezy od materialu, nie od pokoju.
 -- Przyklad dla pokoju 11: reset=51,21;60,21;55.5,18;55.5,29
 room_defs={}
 for line in all(split([[

1|kot=1,2|reset=1,8;14,8;8,1;8,14|piorko=-|wiatr=0.08|kot_lata=1|kot_spawn=5,5
2|kot=0,0|reset=17,8;30,8;24,1;24,14|piorko=-|wiatr=0|kot_lata=0|kot_spawn=-
3|kot=8,12|reset=33,8;46,8;40,1;40,14|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
4|kot=5,8|reset=49,8;62,8;56,1;56,14|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
5|kot=8,12|reset=65,8;78,8;72,1;72,14|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
6|kot=10,15|reset=81,8;94,8;88,1;88,14|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
7|kot=0,0|reset=97,8;110,8;104,1;104,14|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-

8|kot=1,2|reset=1,24;15,18;15,18;12,30|piorko=8,23|wiatr=-0.10|kot_lata=1|kot_spawn=7,17
9|kot=7,11|reset=17,18;30,18;17,18;29,30|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
10|kot=4,7|reset=33,24;46,24;40,17;40,30|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
11|kot=3,5|reset=49,24;62,24;56,17;56,30|piorko=51.25,20.75|wiatr=0|kot_lata=0|kot_spawn=-
12|kot=5,8|reset=65,24;78,24;72,17;72,30|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
13|kot=8,12|reset=81,24;94,24;88,17;88,30|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
14|kot=10,14|reset=97,24;110,24;104,17;104,30|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-

15|kot=0,0|reset=1,40;14,33;14,33;1,45|piorko=6,40|wiatr=0.10|kot_lata=0|kot_spawn=-
16|kot=1,2|reset=16,33;30,40;27,33;24,46|piorko=-|wiatr=-0.1|kot_lata=0|kot_spawn=-
17|kot=8,12|reset=33,40;46,40;40,33;40,46|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
18|kot=6,10|reset=49,40;62,40;56,33;56,46|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
19|kot=8,12|reset=65,40;78,40;72,33;72,46|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
20|kot=10,15|reset=81,40;94,40;88,33;88,46|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
21|kot=0,0|reset=97,40;110,40;104,33;104,46|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-

22|kot=0,0|reset=1,56;14,56;8,49;8,62|piorko=6,56|wiatr=-0.0|kot_lata=0|kot_spawn=-
23|kot=8,12|reset=17,56;30,56;24,49;24,62|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
24|kot=8,12|reset=33,56;46,56;40,49;40,62|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
25|kot=8,12|reset=49,56;62,56;56,49;56,62|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
26|kot=8,12|reset=65,56;78,56;72,49;72,62|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-
27|kot=8,12|reset=81,56;94,56;88,49;88,62|piorko=-|wiatr=0.10|kot_lata=0|kot_spawn=-
28|kot=8,12|reset=97,56;110,56;104,49;104,62|piorko=-|wiatr=-0.10|kot_lata=0|kot_spawn=-

]],"\n")) do
  local fields=split(line,"|")
  local id=tonum(fields[1])
  if id then
   local data={}
   for n=2,#fields do
    local pair=split(fields[n],"=")
    data[pair[1]]=pair[2]
   end
   local def={}
   def.cat_delay_min,def.cat_delay_max=unpack(split(data.kot))
   def.respawns=room_points(data.reset,id)
   assert(#def.respawns>=1 and #def.respawns<=4,"reset: 1..4 punkty")
   def.wind=tonum(data.wiatr) or 0
   def.cat_flying=data.kot_lata==1
   if data.kot_spawn and data.kot_spawn~="-" then
    def.cat_spawn=room_points(data.kot_spawn,id)[1]
   end
   room_defs[id]=def
   if data.piorko~="-" then
    local f=room_points(data.piorko,id)[1]
    add(feather_defs,{id=id,room=id,x=f[1],y=f[2]})
   end
  end
 end
 -- 75 ponownie sluzy jako drzwi; ruchoma platforma zostala usunieta.
 door_tile=75
 init_switches()
 startgame()
end

--
-- 2. PETLA GRY: LOGIKA I RYSOWANIE
--
function _update()
 if capture then update_capture() return end
 p_safe_ticks=max(0,p_safe_ticks-1)
 t+=1
 update_game()
end


--
-- 3. STAN PTASZKA: START / RESTART
-- To wartosci zmienne podczas gry, nie parametry strojenia.
--
function startgame(return_room,point)
 bumper_fx={}
 p_bumper=false
 p_air_adjust=0
 trail={} trail_ticks=0
 dust_age=0 shake=0 shake_x=0
 -- Reset cofa tylko niezatwierdzone otwarcie pokoju.
 if doors_open[room_id]==1 then doors_open[room_id]=nil end
 vision_room=nil
 max_flaps-=#feathers_pending
 -- Nieudana proba: niezapisane piorka wracaja na miejsce.
 for id in all(feathers_pending) do feathers_collected[id]=nil end
 feathers_pending={}
 p_fire_ticks=0
 -- Punkt startu w pikselach, lewy gorny rog spritea 8x8.
 local spawn_room=return_room or start_room_id
 room_x=(spawn_room-1)%room_cols
 room_y=flr((spawn_room-1)/room_cols)
 room_id=room_at(room_x,room_y)
 for plat in all(crumble[room_id]) do plat.age=0 end
 p_checkpoint=point or (not return_room and room_points(start_position,room_id)[1]) or room_defs[room_id].respawns[1]
 p_x,p_y=unpack(p_checkpoint)
 -- p_vx: predkosc pozioma: minus = lewo, plus = prawo
 -- p_run_dir: kierunek aktualnego rozbiegu
 -- p_vy: predkosc pionowa: minus = gora, plus = dol
 -- p_ground: czy ptaszek stoi na platformie
 p_vx,p_run_ticks,p_run_dir,p_vy,p_left,p_ground=0,0,0,0,false,false
 -- p_wall: -1 sciana po lewej, 1 po prawej, 0 brak
 -- p_refill_pause: pozostale klatki pauzy po machnieciu
 -- p_wall_lock: krotka ochrona kierunku odbicia
 p_wall,p_flap_refill,p_refill_pause,p_wall_lock=0,0,0,0
 p_flaps=max_flaps -- aktualny zapas machniec
 p_wing_time=wing_duration -- licznik animacji; koniec oznacza szybowanie
 dash_held,jump_held=btn(4),btn(5) -- bez powtarzania przy trzymaniu
 p_state="glide" -- aktualna animacja
 p_anim_time=0 -- czas animacji idle/walk/glide
end

--
-- 4. STEROWANIE I FIZYKA (RAZ NA KLATKE)
--
function update_game()
 for fx in all(bumper_fx) do
  fx[3]-=1
  if fx[3]<=0 then del(bumper_fx,fx) end
 end
 shake=max(0,shake-1) dust_age=max(0,dust_age-1)
 for plat in all(crumble[room_id]) do
  if plat.age>0 then plat.age=(plat.age+1)%150 end
 end
 update_trail()
 -- Regeneracja dziala niezaleznie od uzywania skrzydel.
 update_flap_refill()
 p_wall_lock=max(0,p_wall_lock-1)
 p_wing_time=min(p_wing_time+1,wing_duration)
 local old_wall=p_wall
 if not p_ground then p_wall=touching_wall() else p_wall=0 end
 if not p_ground and old_wall~=0 and p_wall==0 and p_wall_lock==0 then
  -- Puszczenie strzalki: odejdz od sciany, takze pod wiatr.
  p_vx=-old_wall*0.18 p_wall_lock=4 p_air_adjust=0
 end
 local direction=0
 if btn(0) then direction-=1 end
 if btn(1) then direction+=1 end

 if p_ground and direction~=0 and p_wall_lock==0 then
  p_left=direction<0
 end

 if p_ground then
  p_air_adjust=0
  -- TYLKO ZIEMIA: strzalki buduja rozped i czas rozbiegu.
  if direction~=0 then
   if direction*p_vx<0 then
    p_run_ticks,p_run_dir=0,0
    if abs(p_vx)<=room_ground_brake() then
     p_vx=0
    else
     p_vx+=direction*room_ground_brake()
    end
   else
    if direction~=p_run_dir then p_run_ticks=0 end
    p_run_dir=direction
    -- Narastajace przyspieszenie daje paraboliczny rozbieg.
    local acc=move_acc+acc_growth*p_run_ticks
    p_run_ticks=min(p_run_ticks+1,ramp_ticks)
    p_vx=mid(-ground_max_speed,p_vx+direction*acc,ground_max_speed)
   end
  else
   p_run_ticks,p_run_dir=0,0
   p_vx*=room_ground_drag()
   if abs(p_vx)<0.03 then p_vx=0 end
  end
 else
  -- Usun poprzednia korekte: bonus nie kumuluje sie co klatke.
  p_run_ticks,p_run_dir=0,0
  p_vx=p_vx/(1+p_air_adjust)*air_drag
  local target=0
  if p_vy>=0 and p_wall_lock==0 then
   if abs(p_vx)<0.12 and direction~=0 then p_vx=direction*0.12 end
   target=direction*sgn(p_vx)*air_correction
  end
  p_air_adjust+=mid(-0.04,target-p_air_adjust,0.04)
  p_vx*=1+p_air_adjust
 end
 if not p_ground and p_wall~=0 then p_left=p_wall>0 end

 -- 4b. O/Z = DASH, X = W GORE. Natychmiast po nowym nacisnieciu.
 -- Jednoczesne nacisniecie: pierwszenstwo lotu w gore, tylko jedno piorko.
 local dash_down,jump_down=btn(4),btn(5)
 local jump=jump_down and not jump_held
 if p_flaps>0 and (jump or dash_down and not dash_held) then
  shake=2 sfx(flap_sfx)
  if p_ground then start_dust() end
  p_vy=-(jump and flap_speed or short_lift)
  p_flap_dir=p_left and -1 or 1
  local wall=not p_ground and touching_wall(true) or 0
  if wall~=0 then
   p_flap_dir=-wall
   p_left=p_flap_dir<0
   p_wall_lock=wall_steer_ticks
   p_wall=0
  end
  p_air_adjust=0
  p_vx=p_flap_dir*(jump and hold_drift or dash_speed)
  trail_ticks=jump and 10 or 18
  p_refill_pause=flap_refill_pause_ticks
  p_flaps-=1
  p_wing_time,p_ground=0,false
 end
 dash_held,jump_held=dash_down,jump_down

 p_incoming=p_vx
 move_horizontal()

 local old_bottom=p_y+hit_bottom
 local pull=gravity
 local terminal=fall_speed
 -- Ponizej 0.8 px/klatke w bok opadanie narasta szybciej.
 -- Bez ruchu: limit 1.16 zamiast 0.68; slizg po scianie bez zmian.
 if p_vy>=0 then
  local stall=max(0,0.8-abs(p_vx))
  pull=glide_gravity+stall*0.03
  terminal+=stall*0.6
  -- Puszczone strzalki: o 25% szybsze narastanie i limit opadania.
  if not btn(0) and not btn(1) then pull*=1.25 terminal*=1.25 end
 end
 p_wall=touching_wall()
 if not p_ground and p_wall~=0 and p_vy>=0 then
  terminal=min(terminal,wall_slide_speed)
 end
 p_vy=mid(-max_rise_speed,p_vy+pull,terminal)
 local next_y=p_y+p_vy
 local was_grounded=p_ground -- odroznia nowe ladowanie od stania
 p_ground=false

 if p_vy>=0 then
  local first_row=flr(old_bottom/8)
  local last_row=flr((next_y+hit_bottom)/8)
  local left_tile=flr((p_x+hit_left)/8)
  local right_tile=flr((p_x+hit_right-0.001)/8)
  for row=first_row,last_row do
   local top=row*8
   if old_bottom<=top and next_y+hit_bottom>=top then
    if solid_tile(left_tile,row) or solid_tile(right_tile,row) then
     next_y=top-hit_bottom
     p_vy,p_ground=0,true
     break
    end
   end
  end
 else
  local old_top=p_y+hit_top
  local new_top=next_y+hit_top
  for row=flr(old_top/8),flr(new_top/8),-1 do
   local ceiling=(row+1)*8
   if old_top>=ceiling and new_top<ceiling then
    local left=flr((p_x+hit_left)/8)
    local right=flr((p_x+hit_right-0.001)/8)
    if full_tile(left,row) or full_tile(right,row) then
     next_y=ceiling-hit_top
     p_vy=0
     break
    end
   end
  end
 end
 if p_vy>=0 then
  local floor=crumble_floor(p_x+hit_left,p_x+hit_right,old_bottom,next_y+hit_bottom)
  if floor then next_y=floor-hit_bottom p_vy=0 p_ground=true end
 end
 p_y=next_y
 update_bumper(old_bottom)
 -- Upadek na kolce: wspolna scena zaciemnienia, odrodzenie w tym pokoju.
 if touching_spikes() then
  capture={age=0,x=p_x,y=p_y,radius=max(32,bird_vision_radius()),spike=true}
  return
 end
 if p_ground and not was_grounded then start_dust() end
 -- Lod zachowuje zasade braku odnawiania piorek.
 if p_ground and not was_grounded and not ground_is_ice() and not ground_has(fire_tile) then
  p_flaps=min(max_flaps,p_flaps+1)
 end
 update_fire()
 update_room()
 p_wall=0
 if not p_ground then p_wall=touching_wall() end
 -- Kontakt mogl powstac dopiero przy ruchu w tej klatce.
 if p_wall~=0 then
  p_left=p_wall>0
 end
 update_animation()
 update_feathers()
 update_cat()
 if not capture then update_switches() end
end

-- Wolny lot oraz stanie na lodzie/ogniu wstrzymuja regeneracje.
-- Postep 0..1 pozostaje przy zmianie podloza i machnieciu.
function update_flap_refill()
 if p_refill_pause>0 then
  p_refill_pause-=1
  return
 end
 if p_flaps>=max_flaps then
  p_flap_refill=0
  return
 end
 -- Ziemia i zsuwanie po przyczepnej scianie laduja caly zapas po jednym.
 if p_ground then
  if ground_is_ice() or ground_has(fire_tile) then return end
 elseif p_vy<0 or touching_wall()==0 then
  return
 end
 p_flap_refill+=1/max(1,ground_refill_ticks)
 if p_flap_refill>=0.999 then
  p_flaps=min(max_flaps,p_flaps+1)
  p_flap_refill=0
 end
end

--
-- 4i. SWIAT Z RECZNIE RYSOWANYCH POKOI
-- room_x / room_y: kolumna i wiersz OD ZERA, room_id: ustawienia pokoju.
-- p_x / p_y: lokalna pozycja ptaszka w aktualnym pokoju.
-- Przejscie przesuwa tylko lokalne wspolrzedne o 128 pikseli.
-- Zachowujemy predkosci, zapas machniec, przytrzymanie i animacje.
--
function room_at(x,y)
 if x<0 or y<0 or x>=room_cols or y>=room_rows then return 0 end
 return 1+y*room_cols+x
end

function set_room(x,y,entry)
 bumper_fx={}
 p_bumper=false
 dust_age=0
 trail={} trail_ticks=0
 if doors_open[room_id]==1 then doors_open[room_id]=2 end
 -- Wyjscie zatwierdza juz otrzymane machniecia; nie dodaje ich ponownie.
 feathers_pending={}
 room_x=x
 room_y=y
 room_id=room_at(x,y)
 local points=room_defs[room_id].respawns
 p_checkpoint=points[entry] or points[1]
 cat_begin_travel(room_id)
end

function room_ground_drag()
 if ground_is_ice() then return ice_ground_drag end
 return ground_drag
end

function room_ground_brake()
 if ground_is_ice() then return ice_ground_brake end
 return ground_brake
end

-- Ograniczenie do 0..63 chroni animacje i wspoldzielona pamiec mapy.
function ice_tile(tile)
 return tile>=0 and tile<64 and tile%16>=8 and tile%16<=10
end

-- Kolumna 14 (14,30,46,62) to tlo, bez kolizji i obrazen.
-- Kolumna 15 to kolce; obrazenia tylko na kolorowych pikselach.
function spike_tile(tile)
 return tile>=0 and tile<64 and tile%16==15
end

function fire_tile(tile)
 return tile>=0 and tile<64 and tile%16>=11 and tile%16<=12
end

-- Sprawdzamy oba kafelki bezposrednio pod stopami.
function ground_has(test)
 if not p_ground then return false end
 local row=flr((p_y+hit_bottom+0.001)/8)
 for col=flr((p_x+hit_left)/8),flr((p_x+hit_right-0.001)/8) do
  if test(area_tile(col,row)) then return true end
 end
 return false
end

function ground_is_ice()
 return ground_has(ice_tile)
end

-- Czas kontaktu z lawa: chodzenie i postoj; zejscie zeruje licznik.
-- Zapas maksymalny i zebrane znajdzki pozostaja bez zmian.
function update_fire()
 if not ground_has(fire_tile) then p_fire_ticks=0 return end
 p_fire_ticks+=1
 if p_fire_ticks>=max(1,fire_drain_ticks) then
  p_fire_ticks=0
  p_flaps=max(0,p_flaps-1)
 end
end

function update_room()
 -- Przejscia zaleza od granic swiata.
 if p_x+4>=128 then
  if room_at(room_x+1,room_y)~=0 then
   p_x-=128
   set_room(room_x+1,room_y,1)
  else
   p_x,p_vx,p_run_ticks=120,0,0
  end
 elseif p_x+4<0 then
  if room_at(room_x-1,room_y)~=0 then
   p_x+=128
   set_room(room_x-1,room_y,2)
  else
   p_x,p_vx,p_run_ticks=0,0,0
  end
 end
 -- Ten sam lot trwa w pokoju wyzej albo nizej.
 if p_y+4>=128 then
  if room_at(room_x,room_y+1)~=0 then
   p_y-=128
   set_room(room_x,room_y+1,3)
  else
   -- Upadek poza dolna granice calego swiata: powrot do startu.
   startgame()
  end
 elseif p_y+4<0 then
  if room_at(room_x,room_y-1)~=0 then
   p_y+=128
   set_room(room_x,room_y-1,4)
  else
   -- Nad swiatem nie ma pokoju: konczymy wznoszenie.
   p_y=0 p_vy=max(0,p_vy)
  end
 end
end

function area_tile(tile_x,tile_y)
 -- Kolizje czytamy tylko z prawdziwej mapy, rowniez w sasiednim pokoju.
 local dx=flr(tile_x/16)
 local dy=flr(tile_y/16)
 local id=room_at(room_x+dx,room_y+dy)
 if id==0 then return 0 end
 local tile=mget(room_x*16+tile_x,room_y*16+tile_y)
 if doors_open[id] then
  if tile==door_tile then return 0 end
  return button_pairs[tile] or tile
 end
 return tile
end

-- Kolizje wynikaja tylko z ID. Lista one_way_tiles przepuszcza od dolu i bokow.
function one_way_tile(tile)
 for id in all(one_way_tiles) do
  if tile==id then return true end
 end
 return false
end

function solid_tile(x,y)
 return full_tile(x,y,true)
end

-- Wspolna klasyfikacja kolizji: floor uwzglednia platformy jednostronne.
function full_tile(x,y,floor)
 local tile=area_tile(x,y)
 if tile==door_tile then return true end
 if button_pairs[tile-tile%2] then return false end
 return tile~=0 and not spike_tile(tile) and (ice_tile(tile) or
  (floor or not one_way_tile(tile)) and (wall_tile_types[tile]~=nil or one_way_tile(tile)))
end

function wall_type_at(x,y)
 if not full_tile(x,y) or ice_tile(area_tile(x,y)) or area_tile(x,y)==door_tile then return 0 end
 local kind=wall_tile_types[area_tile(x,y)]
 if kind==nil then return 1 end
 return kind
end

function touching_wall(tap)
 p_wall_type=0
 if p_wall_lock>0 then return 0 end
 local top=flr((p_y+hit_top)/8)
 local bottom=flr((p_y+hit_bottom-0.001)/8)
 local left=flr((p_x+hit_left-0.01)/8)
 local right=flr((p_x+hit_right+0.01)/8)
 for row=top,bottom do
  local kind=wall_type_at(left,row)
  if (tap and full_tile(left,row)) or (kind>0 and btn(0) and not btn(1)) then p_wall_type=kind return -1 end
  kind=wall_type_at(right,row)
  if (tap and full_tile(right,row)) or (kind>0 and btn(1) and not btn(0)) then p_wall_type=kind return 1 end
 end
 return 0
end

-- Kolizja boczna bada przekroczenie krawedzi, nie tylko pozycje koncowa.
-- Stojac na platformie, nie zahaczamy bokiem o kafelek pod stopami.
-- Czytanie przez area_tile obsluguje rowniez sciane w sasiednim pokoju.
function move_horizontal()
 -- Wiatr zmienia droge lotu, nie zapisana sile machniecia.
 -- Zaczep dziala tylko przy strzalce do sciany; puszczenie odsuwa ptaszka.
 local drift=room_defs[room_id].wind
 if p_ground or p_wall_lock>0 or touching_wall()~=0 then drift=0 end
 local movement=p_vx+drift
 local next_x=p_x+movement
 local top=flr((p_y+hit_top)/8)
 local bottom=flr((p_y+hit_bottom-0.001)/8)
 local hit=false
 if movement>0 then
  local old_edge=p_x+hit_right
  local new_edge=next_x+hit_right
  for col=flr(old_edge/8),flr(new_edge/8) do
   local wall=col*8
   if old_edge<=wall and new_edge>wall then
    for row=top,bottom do
     if full_tile(col,row) then
      next_x=wall-hit_right hit=true break
     end
    end
   end
   if hit then break end
  end
 elseif movement<0 then
  local old_edge=p_x+hit_left
  local new_edge=next_x+hit_left
  for col=flr(old_edge/8),flr(new_edge/8),-1 do
   local wall=(col+1)*8
   if old_edge>=wall and new_edge<wall then
    for row=top,bottom do
     if full_tile(col,row) then
      next_x=wall-hit_left hit=true break
     end
    end
   end
   if hit then break end
  end
 end
 p_x=next_x
 if hit then
  -- Zderzenie zatrzymuje; dopiero nacisniecie przycisku odbija od sciany.
  if p_vx*movement>=0 then p_vx=0 end
  p_run_ticks,p_run_dir=0,0
 end
end

function draw_area()
 -- FLIP-SCREEN: jeden wycinek 16x16 kafelkow, poczatek ekranu (0,0).
 -- Bez dodatkowej siatki i bez przestawiania pokojow.
 map(room_x*16,room_y*16,0,0,16,16)
 -- Po odbiciu pokazujemy klatke 13 przez 0.2 s, potem wraca 14.
 for fx in all(bumper_fx) do
  rectfill(fx[1],fx[2],fx[1]+7,fx[2]+7,0)
  spr(13,fx[1],fx[2])
 end
 for plat in all(crumble[room_id]) do
  rectfill(plat.x,plat.y,plat.x+7,plat.y+7,0)
  if plat.age<30 or plat.age>=120 then
   spr((plat.age<15 or plat.age>=135) and 91 or 107,plat.x,plat.y)
  end
 end
 if doors_open[room_id] then
  for item in all(room_devices[room_id]) do
   rectfill(item[1],item[2],item[1]+7,item[2]+7,0)
   if item[3]~=door_tile then spr(button_pairs[item[3]],item[1],item[2]) end
  end
 end
end

--
-- 5. WYBOR ANIMACJI
-- W powietrzu: pojedyncze machniecie, potem szybowanie.
-- Na ziemi: rzeczywista predkosc wybiera chodzenie albo stanie.
--
function update_animation()
 local state="idle"
 if not p_ground then
  state="glide"
  if p_wing_time<wing_duration then state="fly" end
 elseif abs(p_vx)>0.03 then
  state="walk"
 end
 if state~=p_state then
  p_state=state
  p_anim_time=0
 else
  p_anim_time+=1
 end
end

--
-- 6. RYSOWANIE SWIATA I PTASZKA
--
function _draw()
 camera()
 if capture then draw_capture() return end
 cls(0)
 shake_x=shake>0 and shake%2 or 0
 camera(shake_x,0)
 draw_wind_rain()
 draw_trail() -- pod terenem i mgla; nie przeslania ptaszka
 draw_area()
 draw_dust()
 draw_feathers()
 draw_cat() -- kot pod maska: poza widokiem znika razem z terenem
 draw_darkness()
 draw_fog_exceptions()
 -- Korekta grafiki o 1 px w gore: stopy nie zapadaja sie w platforme.
 drawspr(getframe(p_anims[p_state]),p_x,p_y-1,10,p_left)
 camera()
 draw_hud()
end

-- KOT: ptaszek przekazuje mu widocznosc, bez osobnego pola widzenia.
-- Tak jak kolo ptaszka, wykrywanie nie sprawdza scian.
function bird_vision_radius()
 local radius=vision_radius
 if radius<=0 then return 0 end
 local period=max(1,vision_period)
 return flr(mid(8,radius+sin((t%period)/period)*(vision_breathe),128)+0.5)
end

function cat_can_stand(x,y)
 if x<0 or x>120 then return false end
 local left=flr((x+1)/8)
 local right=flr((x+7-0.001)/8)
 local top=flr((y+1)/8)
 local bottom=flr((y+8-0.001)/8)
 for row=top,bottom do
  if full_tile(left,row) or full_tile(right,row) then return false end
 end
 local floor_y=flr((y+8)/8)
 -- Nie przechodzi przez sciany i nie wchodzi nad przepasc.
 return solid_tile(left,floor_y) and solid_tile(right,floor_y)
end

-- Czy pokoj dopuszcza kota? Brak ustawien dziala jak 0..0.
function cat_room_enabled(id)
 local def=room_defs[id]
 if def==nil then return false end
 return max(def.cat_delay_min or 0,def.cat_delay_max or 0)>0
end

function cat_begin_travel(destination)
 if not cat_room_enabled(destination) then
  cat,cat_room,cat_destination=nil,nil,nil
  return
 end
 -- Pamietamy skad przyszedl kot ZANIM wyczyscimy jego pokoj i pozycje.
 cat_entry_side=0
 if cat then cat_entry_x=cat.x end
 if cat_room then
  local from_x=(cat_room-1)%room_cols
  local to_x=(destination-1)%room_cols
  if to_x<from_x then cat_entry_side=1 end -- idzie w lewo: wchodzi z prawej
  if to_x>from_x then cat_entry_side=-1 end -- idzie w prawo: wchodzi z lewej
 end
 local def=room_defs[destination]
 local low=max(0,def.cat_delay_min or 0)
 local high=max(low,def.cat_delay_max or 0)
 -- Limit zapobiega przepelnieniu liczb PICO-8: maks. 600 s.
 low=min(low,600) high=min(high,600)
 cat_travel=max(1,flr((low+rnd(high-low))*30))
 cat_destination=destination
 cat_room,cat,cat_spawn_checked=nil,nil,nil
end

-- Kontakt lapie ptaszka w kazdym stanie: chodzenie, przykuc, skok i opadanie.
-- Sprawdzamy po ruchu obu postaci; ochrona po powrocie nadal obowiazuje.
function update_cat()
 update_cat_behavior()
 if not capture and cat and cat_room==room_id and
    p_safe_ticks==0 and cat_touches_bird() then
  begin_capture()
 end
end

function update_cat_behavior()
 if not cat_started then
  cat_started=true
  cat_begin_travel(room_id)
 end
 if cat_destination then
  if not cat_room_enabled(cat_destination) then
   cat_destination,cat_started=nil,false
   return
  end
  cat_travel=max(0,cat_travel-1)
  if cat_travel>0 then return end
  cat_room=cat_destination
  cat_destination=nil
 end
 if not cat_room then return end
 if room_id~=cat_room then cat_begin_travel(room_id) return end
 if not cat_room_enabled(cat_room) then cat=nil return end
 if room_defs[room_id].cat_flying then update_flying_cat() return end
 if not cat then
  if cat_spawn_checked==cat_room and t%30~=0 then return end
  cat_spawn_checked=cat_room
  -- Wybieramy bezpieczna podloge najblizej WLASCIWEJ krawedzi.
  -- Miejsce wejscia wybieramy w dolnych 6 rzedach; dalej kot skacze i spada.
  -- Przy przejsciu pionowym zachowujemy przyblizona pozycje pozioma.
  local target_x=cat_entry_x
  if cat_entry_side==-1 then target_x=0 end
  if cat_entry_side==1 then target_x=120 end
  local best=nil
  local point=room_defs[room_id].cat_spawn
  if point then
   if not cat_can_stand(point[1],point[2]) then return end
   best={x=point[1],y=point[2]}
  end
  local best_distance=point and -1 or 129
  for row=15,10,-1 do
   for col=0,15 do
    local x=col*8 local y=row*8-8
    local correct_side=cat_entry_side==0 or
     (cat_entry_side==-1 and x<=56) or (cat_entry_side==1 and x>=64)
    local distance=abs(x-target_x)
    if correct_side and distance<best_distance and cat_can_stand(x,y) then
     best={x=x,y=y}
     best_distance=distance
    end
   end
  end
  -- Nie przenosimy kota na przeciwna strone, gdy przy wejsciu brak podlogi.
  if not best then return end
  local entry_dir=-cat_entry_side
  cat={x=best.x,y=best.y,safe_x=best.x,safe_y=best.y,dir=entry_dir,left=entry_dir<0,timer=30,anim=0,moving=false,
   alert=false,notice=0,react=0,waiting=false,entry_ticks=20,
   attack="patrol",cooldown=0,jump_retry=0,vy=0,vx=0,grounded=true}

 end
 local radius=bird_vision_radius()
 local dx=cat.x+4-mid(0,p_x+4,127)
 local dy=cat.y+4-mid(0,p_y+3,127)
 local seen=radius<=0 or dx*dx+dy*dy<=radius*radius
 if seen then cat.notice=cat_notice_ticks else cat.notice=max(0,cat.notice-1) end
 cat.alert=cat.notice>0
 if cat.jump then update_cat_jump() return end
 if not cat.grounded then update_cat_air() return end
 cat.jump_retry=max(0,cat.jump_retry-1)
 cat.seek_timer=max(0,(cat.seek_timer or 0)-1)
 if not cat.alert or dy<=8 then cat.seek_x=nil end
 if cat.alert and dy>8 and cat.entry_ticks<=0 and cat.seek_timer==0 then
  cat.seek_timer=cat_seek_ticks
  if not cat.seek_x then cat.seek_x=cat_find_approach() end
 end
 if update_cat_attack(dx,dy) then return end
 local speed=cat_walk_speed
 if cat.entry_ticks>0 then
  -- Pierwsze kroki do wnetrza pokoju, zanim zacznie losowac kierunek.
  cat.entry_ticks-=1
  cat.dir=-cat_entry_side
 elseif cat.alert then
  speed=cat_chase_speed
  if cat.seek_x then
   local delta=cat.seek_x-cat.x
   cat.dir=delta<0 and -1 or 1
   cat.waiting=false
   if abs(delta)<=cat_chase_speed then
    cat.seek_x,cat.dir,cat.jump_retry=nil,0,0
   end
  else
  -- Dwa progi zapobiegaja dreptaniu na granicy jednego dystansu.
  if abs(dx)<=cat_stop_margin and dy<=8 then cat.waiting=true end
  if abs(dx)>=cat_resume_margin or dy>8 then cat.waiting=false end
  cat.react=max(0,cat.react-1)
  if cat.waiting then
   cat.dir=0 -- zachowaj zwrot spritea podczas postoju
  elseif cat.react<=0 then
   cat.dir=abs(dx)<cat_stop_margin and 0 or (dx>0 and -1 or 1)
   cat.react=cat_react_ticks
  end
  end
  cat.timer=0
 else
  cat.waiting,cat.react=false,0
  cat.timer-=1
  if cat.timer<=0 then
   cat.dir=flr(rnd(3))-1 -- lewo, postoj albo prawo
   cat.timer=30+flr(rnd(61)) -- decyzja co 1..3 s
  end
 end
 local nx=cat.x+cat.dir*speed
 local moving=cat.dir~=0 and cat_space_clear(nx,cat.y)
 if cat.seek_x and (not moving or not cat_can_stand(nx,cat.y)) then
  cat.seek_x=nil cat.seek_timer=cat_seek_ticks
  cat.dir,moving=0,false
 end
 -- Podskok na platforme; faktyczny kontakt z ptaszkiem sprawdza update_cat().
 if cat.alert and cat.entry_ticks<=0 and cat.jump_retry==0 and
    (not moving or dy>8) then
  local jump_dir=cat.dir
  if jump_dir==0 then jump_dir=dx>0 and -1 or 1 end
  if not cat.seek_x and (try_cat_jump(jump_dir) or try_cat_jump(-jump_dir)) then return end
 end
 if moving then
  cat.left=cat.dir<0
 elseif not cat.alert and cat.dir~=0 then
  -- cat.timer: chwila postoju przy scianie lub przepasci
  cat.dir,cat.timer=0,20
 end
 if moving~=cat.moving then cat.anim=0 else cat.anim=(cat.anim+1)%(cat_anim_ticks*4) end
 cat.vx=0
 if moving then cat.vx=cat.dir*speed end
 cat_physics(cat,cat.vx,false)
 cat.moving=moving
end

-- ZNAJDZKI: natychmiastowe machniecie; reset cofa zdobycz przed wyjsciem.
function update_feathers()
 for feather in all(feather_defs) do
  if feather.room==room_id and not feathers_collected[feather.id] and
   p_x+hit_right>feather.x+1 and p_x+hit_left<feather.x+7 and
   p_y+hit_bottom>feather.y+1 and p_y+hit_top<feather.y+7 then
   feathers_collected[feather.id]=true
   add(feathers_pending,feather.id)
   max_flaps+=1
   p_flaps+=1
  end
 end
end

function draw_feathers()
 local frame=feather_anim+flr(t/8)%4
 for feather in all(feather_defs) do
  if feather.room==room_id and not feathers_collected[feather.id] then
   spr(frame,feather.x,feather.y)
  end
 end
end

-- FIZYKA KOTA: spadanie oraz kolizje, rowniez w scenie schwytania.
-- Brak podlogi nie blokuje ruchu poziomego; kot moze zejsc z krawedzi.
function cat_space_clear(x,y)
 for row=flr((y+1)/8),flr((y+8-0.001)/8) do
  for col=flr((x+1)/8),flr((x+7-0.001)/8) do
   if row>=0 and row<16 and col>=0 and col<16 and full_tile(col,row) then
    return false
   end
  end
 end
 return true
end

function cat_physics(body,vx,escape)
 -- Odtworz ostatnie bezpieczne miejsce, gdy teren wszedl w hitbox.
 if not cat_space_clear(body.x,body.y) and body.safe_x then
  body.x=body.safe_x body.y=body.safe_y body.vy,body.vx=0,0
  vx=0
 end
 -- Male kroki poziome zapobiegaja przechodzeniu przez sciany.
 local steps=max(1,ceil(abs(vx)))
 for step=1,steps do
  local nx=body.x+vx/steps
  if not escape then nx=mid(0,nx,120) end
  if cat_space_clear(nx,body.y) then body.x=nx else body.vx=0 break end
 end
 body.vy=min(cat_fall_speed,(body.vy or 0)+cat_gravity)
 local ny=body.y+body.vy
 local left=flr((body.x+1)/8)
 local right=flr((body.x+7-0.001)/8)
 body.grounded=false
 if body.vy>=0 then
  local feet=body.y+8
  for row=flr(feet/8),flr((ny+8)/8) do
   local top=row*8
   if row>=0 and row<16 and feet<=top and ny+8>=top then
    local hit=false
    for col=left,right do
     if col>=0 and col<16 and solid_tile(col,row) then hit=true end
    end
    if hit then ny=top-8 body.vy,body.grounded=0,true break end
   end
  end
 else
  -- Sufity jednostronnych platform nie blokuja wybicia.
  for row=flr((body.y+1)/8),flr((ny+1)/8),-1 do
   local bottom=(row+1)*8
   if body.y+1>=bottom and ny+1<bottom then
    local hit=false
    for col=left,right do
     if row>=0 and row<16 and col>=0 and col<16 and full_tile(col,row) then hit=true end
    end
    if hit then ny=bottom-1 body.vy=0 break end
   end
  end
 end
 if body.vy>=0 then
  local floor=crumble_floor(body.x+1,body.x+7,body.y+8,ny+8)
  if floor then ny=floor-8 body.vy=0 body.grounded=true end
 end
 if cat_space_clear(body.x,ny) then
  body.y=ny
  body.safe_x=body.x body.safe_y=body.y
 else
  body.vy=0
  if body.safe_x then body.x=body.safe_x body.y=body.safe_y end
 end
end

function update_cat_air()
 cat_physics(cat,cat.vx or 0,false)
 cat.anim=(cat.anim+1)%(cat_anim_ticks*4)
 -- Kontakt w locie i podczas spadania obsluguje wspolne update_cat().
 if cat.grounded then
  cat.attack="patrol" cat.cooldown=cat_attack_cooldown
  cat.waiting,cat.react,cat.anim,cat.vx=false,0,0,0
 end
 if cat.y>136 then
  -- Przepasc bez podlogi: powrot po zwyklym czasie wejscia pokoju.
  local destination=cat_room
  cat_begin_travel(destination)
 end
end

-- SKOK KOTA: sprawdzamy CALY tor przed startem, bez osobnego pathfindingu.
function cat_body_clear(x,y)
 if x<0 or x>120 or y<0 or y>120 then return false end
 return cat_space_clear(x,y)
end

function cat_jump_point(x,y,tx,ty,u)
 -- Najpierw wybicie w gore przy krawedzi, potem przelot i lagodne ladowanie.
 if u<0.45 then return x,y+(ty-cat_jump_clearance-y)*(u/0.45) end
 local v=(u-0.45)/0.55
 return x+(tx-x)*v,ty-cat_jump_clearance+cat_jump_clearance*v*v
end

-- Tania kontrola sufitu: gora co 2 px, ten sam hitbox co zwykly ruch.
function cat_up_clear(x,y,height)
 for rise=0,height,2 do
  if not cat_body_clear(x,y-rise) then return false end
 end
 return cat_body_clear(x,y-height)
end

-- Szukaj najblizszego miejsca z podloga, wolnym wybiciem i platforma obok.
-- Kazdy krok podejscia musi miec podparcie; nie prowadzi kota w przepasc.
function cat_find_approach()
 for distance=8,cat_seek_reach,8 do
  for side=-1,1,2 do
   local x=cat.x+side*distance
   local clear=true
   for step=1,distance do
    if not cat_can_stand(cat.x+side*step,cat.y) then clear=false break end
   end
   if clear then
    for rise=8,cat_jump_height,8 do
     if cat_up_clear(x,cat.y,rise+cat_jump_clearance) then
      for reach=8,cat_jump_reach,8 do
       if cat_can_stand(x-side*reach,cat.y-rise) and cat_clear_arc(x,cat.y,x-side*reach,cat.y-rise,cat_jump_ticks) then return x end
      end
     end
    end
   end
  end
 end
 return nil
end

function try_cat_jump(direction)
 cat.jump_retry=cat_jump_retry
 for rise=8,cat_jump_height,8 do
  local ty=cat.y-rise
  for distance=0,cat_jump_reach,8 do
   local tx=cat.x+direction*distance
   if cat_can_stand(tx,ty) then
    local ticks=min(cat_jump_ticks,max(12,ceil(rise+distance/3)))
    if cat_clear_arc(cat.x,cat.y,tx,ty,ticks) then
     cat.jump={x=cat.x,y=cat.y,tx=tx,ty=ty,age=0,ticks=ticks}
     cat.left=direction<0 cat.moving,cat.anim=false,0
     return true
    end
   end
  end
 end
 return false
end

function update_cat_jump()
 local jump=cat.jump
 jump.age+=1
 local nx,ny=cat_jump_point(jump.x,jump.y,jump.tx,jump.ty,min(1,jump.age/jump.ticks))
 if not cat_body_clear(nx,ny) then
  cat.jump,cat.grounded,cat.vy,cat.vx=nil,false,0,0
  cat.attack="patrol" cat.jump_retry=cat_jump_retry
  return
 end
 cat.x=nx cat.y=ny cat.safe_x=nx cat.safe_y=ny
 if jump.age>=jump.ticks then
  cat.x=jump.tx cat.y=jump.ty cat.jump=nil
  cat.grounded,cat.vy,cat.vx=true,0,0
  cat.jump_retry=cat_jump_retry
  cat.cooldown=15 -- po ladowaniu nie lapie natychmiast
  cat.waiting,cat.react,cat.anim=false,0,0
 end
end

-- ATAK: najpierw czytelny przykuc, potem krotki wypad bez sledzenia celu.
function cat_touches_bird()
 return cat.x+1<p_x+hit_right and cat.x+7>p_x+hit_left and
  cat.y+1<p_y+hit_bottom and cat.y+8>p_y+hit_top
end

function update_cat_attack(dx,dy)
 cat.cooldown=max(0,cat.cooldown-1)
 if cat.attack=="crouch" then
  cat.moving=false
  cat.attack_time+=1
  if cat.attack_time>=cat_crouch_ticks then
   cat.attack="lunge" cat.attack_time,cat.anim=0,0
   if cat.attack_up then
    cat.attack="air" cat.grounded=false
    cat.vy=-cat.attack_lift cat.vx=cat.attack_dir*cat_attack_speed
    if cat.attack_vertical then cat.vx=0 end
   end
  end
  return true
 end
 if cat.attack=="lunge" then
  cat.attack_time+=1
  local nx=cat.x+cat.attack_dir*cat_attack_speed
  cat.moving=cat_space_clear(nx,cat.y)
  cat.vx=cat.attack_dir*cat_attack_speed
  cat_physics(cat,cat.vx,false)
  cat.left=cat.attack_dir<0
  cat.anim=(cat.anim+1)%(cat_anim_ticks*4)
  if not cat.moving or cat.attack_time>=cat_attack_ticks then
   cat.attack="patrol" cat.cooldown=cat_attack_cooldown
   cat.moving,cat.anim,cat.waiting=false,0,true
  end
  return true
 end
 if cat.alert and cat.cooldown==0 and p_safe_ticks==0 and
    cat.entry_ticks<=0 and not cat.seek_x and abs(dx)<=cat_attack_range and dy>=-cat_attack_height and dy<=cat_jump_height and
    (dy<=5 or cat_up_clear(cat.x,cat.y,min(dy,cat_jump_height))) then
  cat.attack="crouch" cat.attack_time,cat.moving=0,false
  cat.attack_up=dy>5
  cat.attack_vertical=cat.attack_up and abs(dx)<=cat_stop_margin
  -- Zamroz cel przed przykucem: gracz moze zrobic unik.
  -- v^2=2*g*h; +g/2 kompensuje grawitacje dodawana przed ruchem.
  cat.attack_lift=min(cat_pounce_speed,sqrt(2*cat_gravity*max(0,dy))+cat_gravity/2)
  cat.attack_dir=dx>0 and -1 or 1
  cat.left=cat.attack_dir<0
  return true
 end
 return false
end

-- SCHWYTANIE: zatwierdzone piorka zostaja; niezatwierdzone wracaja po scenie.
function begin_capture()
 local direction=1
 if cat.x<60 then direction=-1 end -- ucieczka do blizszej krawedzi
 local exit_x=136
 if direction<0 then exit_x=-16 end
 local radius=bird_vision_radius()
 if radius<=0 then radius=128 end
 capture={age=0,x=cat.x,y=cat.y,
  vy=cat.vy or 0,run_vx=(exit_x-cat.x)/max(1,capture_run_ticks),
  left=direction<0,radius=radius}
 -- Ptaszka nie rysujemy, nie ruszamy nim i nie odbieramy piorek.
end

function update_capture()
 capture.age+=1
 -- Ruch i grawitacja sceny dzialaja mimo zamrozonego zegara swiata.
 if capture.age<capture_run_ticks and not capture.spike then
  cat_physics(capture,capture.run_vx,true)
 end
 if capture.age>=capture_run_ticks+capture_black_ticks then
  -- Reset tylko ruchu: pozostaja zdobyte ulepszenia i odwiedzone pokoje.
  -- max_flaps zostaje zachowane, powrot po schwytaniu daje pelny zapas tapniec.
  startgame(room_id,p_checkpoint)
  -- p_safe_ticks: 3 s na odzyskanie kontroli
  p_safe_ticks,vision_room=90,nil
  cat,cat_room,cat_destination=nil,nil,nil
  cat_spawn_checked=nil
  cat_started=true
  -- Kot wraca dopiero po kolejnym czasie przewidzianym dla pokoju.
  if cat_room_enabled(room_id) then
   cat_begin_travel(room_id)
  else
   cat_started=false
  end
  capture=nil
 end
end

function draw_capture()
 cls(0)
 if capture.age>=capture_run_ticks then return end
 draw_area()
 local frame=cat_carry+flr(capture.age/cat_anim_ticks)%4
 if capture.spike then
  -- Czerwony blysk przez pierwsze 0.2 s; czern zostaje bez zmian.
  local flash=capture.age<6
  if flash then for c=1,15 do pal(c,8) end end
  drawspr(getframe(p_anims[p_state]),capture.x,capture.y-1,flash and 8 or 10,p_left)
 else
  spr(frame,capture.x,capture.y,1,1,capture.left)
 end
 local radius=flr(capture.radius*(1-min(1,capture.age/max(1,capture_run_ticks))))
 -- Pelna maska sceny: zadnych wyjatkow 2/3, HUD ani spritea ptaszka.
 draw_mask(capture.x+4,capture.y+4,radius,radius>4 and 4 or 0)
end

function draw_cat()
 if room_id~=cat_room or not cat then return end
 if cat.flying then
  spr(72+flr(t/6)%3,cat.x,cat.y,1,1,cat.left)
  if cat.phase==1 then
   local y=max(0,cat.y-7)
   line(cat.x+4,y,cat.x+4,y+3,8)
   pset(cat.x+4,y+5,8)
  end
  return
 end
 local ani=cat_idle
 if cat.moving then ani=cat_walk end
 local frame=ani+flr(cat.anim/cat_anim_ticks)%4
 if not cat.grounded and not cat.jump then
  frame=cat_jump_anim+2
  if cat.vy<0 then frame=cat_jump_anim+1 end
 elseif cat.jump then
  frame=cat_jump_anim+min(3,flr(cat.jump.age*4/cat.jump.ticks))
 elseif cat.attack=="crouch" then
  local phase=min(3,flr(cat.attack_time*4/cat_crouch_ticks))
  frame=cat_crouch+phase -- jednorazowo, ostatnia klatka czeka na wypad
 end
 spr(frame,cat.x,cat.y,1,1,cat.left)
end

-- 6b. OKRAG WIDOCZNOSCI: sciany nie zaslaniaja terenu wewnatrz kola.
-- Bufor wyjatkow odnawiamy tylko po zmianie pokoju lub vision_room=nil.
function refresh_vision()
 if vision_room~=room_id then
  vision_exceptions={}
  for y=0,15 do
   for x=0,15 do
    local tile=area_tile(x,y)
    for id in all(fog_visible_tiles) do
     if tile~=0 and tile==id then
      -- Buforujemy tylko kolorowe piksele wyjatkow przy wejsciu do pokoju.
      local sx=(tile%16)*8
      local sy=flr(tile/16)*8
      for py=0,7 do
       for px=0,7 do
        local color=sget(sx+px,sy+py)
        if color~=0 then
         add(vision_exceptions,{x*8+px,y*8+py,fog_dim_colors[color+1]})
        end
       end
      end
      break
     end
    end
   end
  end
  vision_room=room_id
 end
end

function draw_darkness()
 local radius=bird_vision_radius()
 if radius<=0 then return end
 local fade=mid(0,vision_fade,radius-1)
 local eye_x=mid(0,p_x+4,127)
 local eye_y=mid(0,p_y+3,127)
 refresh_vision()
 -- Trzy warstwy czerni: pelna, 50%, 25%. Dithering nie zmienia palety.
 -- Wzor jest przezroczysty w przerwach; teren przeswituje przez gradient.
 draw_mask(eye_x,eye_y,radius,fade)
end

-- Bufor osobno dla kazdego promienia: oddychanie nie przelicza pierwiastkow.
-- Pasy po 2 px wygladzaja obrys; nie obliczamy cieni scian.
function draw_vision_edge(eye_x,eye_y,radius)
 if not vision_circles then vision_circles={} end
 local widths=vision_circles[radius]
 if not widths then
  widths={}
  for dy=0,radius do
   widths[dy+1]=flr(sqrt(radius*radius-dy*dy))
  end
  vision_circles[radius]=widths
 end
 for y=0,126,2 do
  local dy=flr(abs(y+0.5-eye_y))
  if dy>=radius then
   rectfill(0,y,127,y+1,0)
  else
   local half_width=widths[dy+1]
   local left=flr(eye_x-half_width)-1
   local right=flr(eye_x+half_width)+1
   if left>=0 then rectfill(0,y,min(127,left),y+1,0) end
   if right<=127 then rectfill(max(0,right),y,127,y+1,0) end
  end
 end
end

-- Odtwarzamy przyciemnione piksele TYLKO tam, gdzie maska dala czern.
-- Dane grafiki i zamiane kolorow liczymy raz, razem z buforem pokoju.
function draw_fog_exceptions()
 if vision_radius<=0 then return end
 for pixel in all(vision_exceptions) do
  if pget(pixel[1]-shake_x,pixel[2])==0 then
   pset(pixel[1],pixel[2],pixel[3])
  end
 end
end









--
-- 7. HUD: PIORKA W PRAWYM GORNYM ROGU
--
function draw_hud()
 -- Piorka HUD: 108 pelne, 109 zuzyte, 110 czesciowe, 111 prawie pelne.
 for n=1,max_flaps do
  local row=flr((n-1)/10)
  local x=118-(min(10,max_flaps-row*10)-1)*10+((n-1)%10)*10
  local y=2+row*10
  if y<=120 then
   local sprite=109
   if n<=p_flaps then
    sprite=108
   elseif n==p_flaps+1 then
    if p_flap_refill>=2/3 then
     sprite=111
    elseif p_flap_refill>=1/3 then
     sprite=110
    end
   end
   spr(sprite,x,y)
  end
 end
end

function getframe(ani)
 -- Machniecie nie ma modulo: nie zapetla sie, kazdy tap restartuje licznik.
 if p_state=="fly" then
  return ani+min(flr(p_wing_time/wing_frame_ticks),3)
 end
 -- Idle i szybowanie: 10 klatek gry na sprite. Chodzenie zalezy od predkosci.
 local frame_ticks=10
 if p_state=="walk" then
  frame_ticks=max(3,8-flr(abs(p_vx)*2))
 end
 return ani+flr(p_anim_time/frame_ticks)%4
end

function drawspr(_spr,_x,_y,_c,_flip)
 palt(0,true) -- czarne piksele ptaszka sa przezroczyste
 pal(6,_c) -- zamiana koloru 6 na podany kolor _c
 spr(_spr,_x,_y,1,1,_flip)
 pal() -- przywrocenie palety po rysowaniu ptaszka
end

-- Stale listy liczb: przecinek = kolejna liczba, srednik = kolejny wiersz.
-- Uzywane tylko przy starcie; wynikiem sa zwykle tabele liczb.
function number_rows(text)
 local rows=split(text,";")
 for i=1,#rows do rows[i]=split(rows[i]) end
 return rows
end




-- Kolce: kolor 0 jest pusty, pozostale piksele grafiki zadaja obrazenia.
-- Sprawdzamy tylko 4x5 pikseli hitboxa ptaszka, rowniez przy ruchu z boku.
function touching_spikes()
 for y=flr(p_y+hit_top),flr(p_y+hit_bottom-0.001) do
  for x=flr(p_x+hit_left),flr(p_x+hit_right-0.001) do
   local tile=area_tile(flr(x/8),flr(y/8))
   if spike_tile(tile) and sget(tile%16*8+x%8,flr(tile/16)*8+y%8)~=0 then return true end
  end
 end
end

-- Wspolny gradient widocznosci i scen resetu.
function draw_mask(eye_x,eye_y,radius,fade)
 fillp()
 draw_vision_edge(eye_x,eye_y,radius)
 if fade>0 then
  fillp(0x5a5a.8)
  draw_vision_edge(eye_x,eye_y,max(1,radius-flr(fade/2)))
  fillp(0xfafa.8)
  draw_vision_edge(eye_x,eye_y,max(1,radius-flr(fade)))
 end
 fillp() -- nie przenos wzoru na ptaszka, HUD
end

-- DRZWI I PRZYCISKI: rysuj je w edytorze mapy, bez wpisywania wspolrzednych.
-- door_tile = ID drzwi, -1 wylacza.
-- Nie zmieniamy mset(): mapa i wspoldzielona pamiec spriteow pozostaja nietkniete.
function init_switches()
 button_pairs={[76]=77,[78]=79,[92]=93,[94]=95}
 doors_open={} -- nil zamkniete, 1 otwarte tymczasowo, 2 zatwierdzone po wyjsciu
 room_devices={}
 crumble={}
 for id=1,room_cols*room_rows do room_devices[id]={} crumble[id]={} end
 for y=0,room_rows*16-1 do
  for x=0,room_cols*16-1 do
   local tile=mget(x,y)
   if tile==91 or tile==107 then
    add(crumble[room_at(flr(x/16),flr(y/16))],{x=x%16*8,y=y%16*8,age=0})
   end
   if tile==door_tile or button_pairs[tile] then
    add(room_devices[room_at(flr(x/16),flr(y/16))],{x%16*8,y%16*8,tile})
   end
  end
 end
end

-- Przycisk jest czujnikiem kontaktu, nie pelnym blokiem. Uzywa hitboxow postaci.
function hits_switch(x1,y1,x2,y2,item)
 return x1<item[1]+8 and x2>item[1] and y1<item[2]+8 and y2>item[2]
end

function update_switches()
 if doors_open[room_id] then return end
 for item in all(room_devices[room_id]) do
  if button_pairs[item[3]] and
   (hits_switch(p_x+hit_left,p_y+hit_top,p_x+hit_right,p_y+hit_bottom,item) or
    (cat and cat_room==room_id and hits_switch(cat.x+1,cat.y+1,cat.x+7,cat.y+8,item))) then
   doors_open[room_id]=1
   vision_room=nil
   return
  end
 end
end

-- DESZCZ WIATRU: krotkie kreski bez jasnych glowek.
-- Rozne dlugosci i warstwy; nawet slaby wiatr ma czytelny kierunek.
-- Predkosc wizualna nie zmienia sily fizycznej. Bez rnd() i tabel czastek.
function draw_wind_rain()
 local wind=room_defs[room_id].wind
 if wind==0 then return end
 local phase=t%512
 local dir=sgn(wind)
 for i=1,28 do
  local layer=1+i%4
  local vx=dir*(0.75+layer*0.25+abs(wind)*4)
  local vy=0.15+(i*7%5)*0.1
  local length=1+i*7%3
  local x=(i*37+phase*vx)%128
  local y=(i*53+phase*vy)%128
  local tail_y=vy*length/abs(vx)
  -- Jednolity kolor calej kreski; rozne dlugosci, skosy i jasnosc.
  local color=13
  if i%3==0 then color=5 elseif i%5==0 then color=6 end
  line(x-dir*length,y-tail_y,x,y,color)
 end
end

-- SMUGA: dluzszy ogon do 8 pojedynczych pikseli, gasnacych z czasem.
function update_trail()
 for dot in all(trail) do
  dot[3]-=1
  if dot[3]<=0 then del(trail,dot) end
 end
 if trail_ticks>0 then
  trail_ticks-=1
  if not p_ground and t%2==0 then add(trail,{p_x+4,p_y+3,16}) end
 end
end

function draw_trail()
 for dot in all(trail) do
  local color=1
  if dot[3]>5 then color=13 end
  if dot[3]>10 then color=12 end
  pset(dot[1],dot[2],color)
 end
end

-- Globalne kafelki edytora -> lokalne piksele fizyki; tylko przy starcie.
function room_points(text,id)
 local points=number_rows(text)
 for point in all(points) do
  point[1]=(point[1]-(id-1)%room_cols*16)*8
  point[2]=(point[2]-flr((id-1)/room_cols)*16)*8
  assert(point[1]>=0 and point[1]<128 and point[2]>=0 and point[2]<128,
   "punkt poza pokojem "..id)
 end
 return points
end


-- 91: 0.5 s, 107: 0.5 s, pustka: 3 s, odbudowa 107/91: po 0.5 s.
-- Cykl zaczyna ladowanie ptaszka lub kota. Odbudowa nie ma jeszcze kolizji.
function crumble_floor(left,right,old,new)
 local floor=nil
 for plat in all(crumble[room_id]) do
  if plat.age<30 and left<plat.x+8 and right>plat.x and old<=plat.y and new>=plat.y then
   floor=min(floor or plat.y,plat.y)
   if plat.age==0 then plat.age=1 end
  end
 end
 return floor
end

-- Test: patrol, ostrzezenie 0.5 s, szarza bez korygowania celu.
function update_flying_cat()
 if cat and not cat_body_clear(cat.x,cat.y) then cat=nil end
 if not cat then
  local point=room_defs[room_id].cat_spawn
  if point and cat_body_clear(point[1],point[2]) then
   cat={x=point[1],y=point[2],flying=true,phase=0,timer=60,dir=1,vy=0}
  end
  return
 end
 cat.timer-=1
 local vx,vy=0,0
 if cat.phase==0 then
  vx=cat.dir*0.33 vy=sin(t/90)*0.12
  local dx,dy=p_x-cat.x,p_y-cat.y
  if cat.timer<=0 and p_safe_ticks==0 and abs(dx)+abs(dy)<48 then
   local length=max(1,max(abs(dx),abs(dy)))
   cat.vx=dx/length*1.32 cat.vy=dy/length*1.32
   cat.phase=1 cat.timer=15
  end
 elseif cat.phase==1 then
  if cat.timer<=0 then cat.phase=2 cat.timer=20 end
 else
  vx=cat.vx vy=cat.vy
  if cat.timer<=0 then cat.phase=0 cat.timer=60 end
 end
 local nx,ny=cat.x+vx,cat.y+vy
 if cat_body_clear(nx,ny) then cat.x=nx cat.y=ny else
  cat.dir=-cat.dir cat.phase=0 cat.timer=60
 end
 if vx~=0 then cat.left=vx<0 end
end

-- Jeden krotki oblok przy starcie/ladowaniu; nie zuzywa rnd().
function start_dust()
 dust_x=p_x+4 dust_y=p_y+hit_bottom-1 dust_age=12
end
function draw_dust()
 if dust_age<=0 then return end
 local age=12-dust_age
 for i=1,6 do
  pset(dust_x+(i-3.5)*age*0.24,dust_y-age*(0.4+i%2*0.15)+age*age*0.035,dust_age>6 and 6 or 5)
 end
end

-- 14: z gory wybija pionowo; z boku odwraca ruch poziomy.
-- Odbicie daje jedno piorko do limitu. Jeden bonus na ciagly kontakt.
function update_bumper(old_bottom)
 local hit,top=false,nil
 for y=flr((p_y+hit_top)/8),flr((p_y+hit_bottom-0.001)/8) do
  for x=flr((p_x+hit_left)/8),flr((p_x+hit_right-0.001)/8) do
   if area_tile(x,y)==14 then
    if not p_bumper then add(bumper_fx,{x*8,y*8,6}) end
    hit=true
    if p_vy>0 and old_bottom<=y*8 then top=y*8 end
   end
  end
 end
 if hit and not p_bumper then
  p_flaps=min(max_flaps,p_flaps+1)
  local direction=p_left and 1 or -1
  if abs(p_incoming)>0.02 then direction=-sgn(p_incoming) end
  p_air_adjust=0
  if top then
   p_y=top-hit_bottom p_vy=-bumper_up
   local side=p_left and -1 or 1
   if abs(p_incoming)>0.02 then side=sgn(p_incoming) end
   p_vx=side*max(abs(p_incoming),0.45)
  else
   p_vx=direction*bumper_speed
   p_vy=min(p_vy,-bumper_lift)
  end
  -- Zwrot spritea i nastepnego machniecia zgodny z faktycznym wybiciem.
  p_left=p_vx<0 p_flap_dir=sgn(p_vx)
  p_ground=false p_wall=0 p_wall_lock=wall_steer_ticks
  p_wing_time=0 trail_ticks=18 shake=2 sfx(flap_sfx)
 end
 p_bumper=hit
end

-- Wspolny test toru: planowanie podejscia i wykonanie skoku.
function cat_clear_arc(x,y,tx,ty,ticks)
 for step=1,ticks*2 do
  local px,py=cat_jump_point(x,y,tx,ty,step/(ticks*2))
  if not cat_body_clear(px,py) then return false end
 end
 return true
end
