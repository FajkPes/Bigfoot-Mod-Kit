BIGFOOT MOD KIT
===============

Co to je
--------
Nastroj na upravu hry Bigfoot za behu: zdravi a chytrost bigfoota,
mnozstvi lootu, delka dne a noci, vlastnosti lovcu, zdravi jednotlivych
hracu a dalsi.

Aplikace je vychozi anglicky. Cestinu prepnes rozbalovacim menu vpravo
nahore. Anglicka verze tohohle souboru je v README.txt.

Poradi kroku
------------
  1-Install.bat    nainstaluje loader a mod do hry (staci jednou)
  3-Play.bat  spusti hru pres Steam a k tomu Mod Manager
  2-Mod-Manager.bat  spusti jen Mod Manager, kdyz uz hra bezi

  Soubory a hlasky instalatoru jsou anglicky, stejne jako aplikace.

  Uninstall.bat    mod vypne a zachova instalaci v datovane zaloze

Mod Manager vyzaduje Microsoft .NET 10 Desktop Runtime x64. Spousteci soubory
jej zkontroluji a pri chybejici instalaci nabidnou oficialni stranku Microsoftu.

Jak to pouzivat
---------------
1. Spust hru a zaloz session (musis byt HOST).
2. V Mod Manageru pockej, az vpravo nahore svitit "hostujes - zmeny plati".
3. Dej "Nacist z hry". Dokud to neudelas, nejde nic odeslat - aplikace musi
   znat skutecna cisla hry, nez smi cokoliv prepsat.
4. Nastav hodnotu a odesli ji tlacitkem "Pouzit" primo u toho radku.

Kazdy radek se odesila zvlast
-----------------------------
Do hry jde jen to, co jsi vyslovene odeslal. Cehokoliv jineho se mod ani
nedotkne - takze zmena jedne veci uz nikdy neprepise dvacet dalsich.

Tlacitko "Pouzit" u radku hodnotu odesle. Stav radku pozna podle barvy
jeho leveho okraje a ramecku toho tlacitka:

  sedy       radek se do hry jeste neposilal
  zeleny     hra tuhle hodnotu drzi
  oranzovy   posilal jsi, ale od te doby jsi hodnotu zmenil

"Reset" vrati radek na to, co hlasila hra pri nacteni hodnot. U veci, ktere
hra nikdy nehlasi - nasobice lootu, pocasi, vykon - vrati neutralni hodnotu.

"pouzit sekci" odesle celou sekci. "Pouzit vse" a "Reset vse" dole se tykaji
uplne vseho a oboji se nejdriv zepta. Vpravo nahore je pocet aktivnich prepisu
a vedle nej hledani - v pres sto radcich se jinak orientuje spatne.

Predvolby
---------
"Ulozit jako..." ulozi vsechno prave vnucovane pod nazvem. "Nacist" posle
ulozenou predvolbu do hry naraz. Prvni polozka "Hodnoty ze hry" neni soubor -
vrati vsechno do puvodniho stavu.

Zalozky
-------
  Bigfoot     vydrz, smysly, pozornost, pohyb
  Lovci       zdravi, kondice/stamina, pad, pacovani utoku bigfoota
  Cas         delka dne a noci, prime pretoceni hodin i dne
  Loot        nasobice predmetu - globalni + kazda vec zvlast
  Svet        pravidla session, nesmrtelnost, zvyrazneni
  Zobrazeni   FOV, treti osoba, citlivost mysi - jen u tebe
  Vykon       konzolove promenne enginu - jen u tebe
  Opravy      obchazeni veci, ktere hra dela spatne
  Akce        jednorazove prikazy (vylecit vsechny, zabit bigfoota...)
  Hraci       kdo je v session, jejich zdravi a prikazy na jednotlivce

Zalozky Zobrazeni a Vykon funguji, i kdyz nehostujes. Nic z nich se
neprenasi po siti a neni to herni vyhoda.

Multiplayer
-----------
Meni to host. Druhy hrac nemusi instalovat nic - hodnoty se mu prenesou
sitovou replikaci hry. Overeno u denni doby; u ostatnich hodnot to
funguje stejnym mechanismem.

Nasobice predmetu (kamery, munice, leky...) nastav PRED zalozenim session.
Loot se generuje pri nacteni mapy, takze pozdejsi zmena uz s rozmistenymi
vecmi nic neudela.

Globalni nasobic "Vse dohromady" se stohuje s tim u konkretni veci:
vse x2 a lekarnicky x3 dela lekarnicky x6.

Bezpecnost
----------
- Zadny soubor hry se nemeni. Pridava se jen dwmapi.dll a slozka ue4ss.
- Hra jde spustit i bez modu, kontrola vlastnictvi pres Steam neni dotcena.
- Hra nema anticheat (jen Steamworks a EOS SDK).
- Vsechny zapisy do hry jsou osetrene a omezene na rozumny rozsah.
- Mod nesaha na disk, kdyz se nic nezmenilo, a herni objekty si drzi v
  kratkodobe pameti - nema tedy proc hru zpomalovat.

Kdyz neco nefunguje
-------------------
- "hra nebezi" v Mod Manageru: hra musi byt spustena a mod nactenty.
- "v menu": jeste nejsi v session.
- "jsi klient": nastavuje host, ne ty.
- Chyba primo v modu se ukaze dole v aplikaci jako "Chyba v modu: ...".
- Kdyz se po zmene mapy hlasi nesmysly, dej Akce > "Znovu nacist objekty".
- Log loaderu: <slozka hry>\Bigfoot\Binaries\Win64\ue4ss\UE4SS.log

Nestandardni instalace hry
--------------------------
Kdyz skripty hru nenajdou (jina platforma nez Steam, druha kopie hry),
nastav pred spustenim promennou BIGFOOT_DIR na slozku s
Bigfoot-Win64-Shipping.exe, napriklad:

  set BIGFOOT_DIR=D:\Hry\Bigfoot\Bigfoot\Binaries\Win64
  1-Install.bat
