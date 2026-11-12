#let accent = rgb("#7a4a2b")
#let dane = json("dry_bean/output/results.json")

#set page(margin: (x: 2.8cm, y: 2.5cm))
#set text(font: "Liberation Serif", size: 11pt, lang: "pl")
#set par(justify: true, leading: 0.75em)
#set heading(numbering: "1.")

#show heading: it => {
  set text(fill: accent)
  it
  v(0.3em)
}
#show figure.caption: it => text(style: "italic", size: 10pt)[#it]
#show raw: set text(font: "Liberation Mono", size: 9.5pt)
#show raw.where(block: true): it => block(width: 100%, breakable: false, it)

#align(center)[
  #strong[POLITECHNIKA ŚWIĘTOKRZYSKA] \
  #strong[Wydział Elektrotechniki, Automatyki i Informatyki]
]

#line(length: 100%)

#table(
  columns: (1fr, 1fr),
  align: center,
  table.cell(colspan: 2)[#strong[Analiza i wizualizacja danych]],
  table.cell(colspan: 2)[#strong[Temat 5:] Selekcja cech i klasyfikacja danych numerycznych z zastosowaniem wybranego klasyfikatora.],
  [#strong[Autor:] \ xxx],
  [#strong[Grupa:] \ yyy],
)

#v(0.6em)
#align(center)[
  #text(size: 18pt, fill: accent)[*Analiza statystyczna zbioru danych Dry Bean*]
]
#v(0.3em)
#line(length: 100%, stroke: 0.5pt + accent)
#v(0.3em)

= Wprowadzenie

Niniejsze sprawozdanie prezentuje wyniki analizy statystycznej zbioru danych *Dry Bean*,
realizowanej w ramach etapu 6 projektu z przedmiotu Analiza i wizualizacja danych. Projekt
wykonywany jest w zespole dwuosobowym, a każda osoba analizuje własny zbiór danych przy użyciu
wspólnego programu w języku Python. Niniejszy dokument dotyczy wyłącznie zbioru Dry Bean;
drugi zbiór, Breast Cancer Wisconsin, opisany jest w osobnym sprawozdaniu.

= Opis zbioru danych

Zbiór #emph[Dry Bean Dataset] pochodzi z repozytorium UCI Machine Learning Repository
(identyfikator 602) i zawiera pomiary #dane.liczba_rekordow ziaren siedmiu odmian fasoli,
uzyskane w wyniku analizy obrazu wykonanego kamerą wysokiej rozdzielczości. Dla każdego ziarna
wyznaczono #dane.liczba_cech cech liczbowych: 12 wymiarów geometrycznych oraz 4 współczynniki
kształtu, a także przypisano jedną z siedmiu klas (odmian).

#figure(
  table(
    columns: (auto, 1fr),
    stroke: (x, y) => if y == 0 { (bottom: 1pt + accent) } else { (bottom: 0.5pt + gray) },
    [*Atrybut*], [*Znaczenie*],
    [Area], [powierzchnia ziarna (liczba pikseli w jego obrysie)],
    [Perimeter], [obwód ziarna],
    [MajorAxisLength], [długość najdłuższej osi ziarna],
    [MinorAxisLength], [długość osi prostopadłej do najdłuższej],
    [AspectRation], [stosunek długości osi głównej do osi mniejszej],
    [Eccentricity], [mimośród elipsy o takich samych momentach co ziarno],
    [ConvexArea], [liczba pikseli najmniejszego wypukłego wielokąta obejmującego ziarno],
    [EquivDiameter], [średnica koła o takiej samej powierzchni jak ziarno],
    [Extent], [stosunek powierzchni ziarna do powierzchni prostokąta opisanego],
    [Solidity], [stosunek powierzchni ziarna do powierzchni jego otoczki wypukłej],
    [roundness], [okrągłość, $4 pi A \/ P^2$],
    [Compactness], [zwartość kształtu, $E_d \/ L$],
    [ShapeFactor1--4], [dodatkowe bezwymiarowe współczynniki kształtu],
    [Class], [odmiana fasoli (klasa): Seker, Barbunya, Bombay, Cali, Dermason, Horoz, Sira],
  ),
  caption: [Atrybuty zbioru Dry Bean (opracowano na podstawie pliku #raw("Dry_Bean_Dataset.txt")).],
)

Poniżej przedstawiono trzy przykładowe rekordy (wybrane kolumny) ze zbioru danych.

#figure(
  table(
    columns: 7,
    stroke: (x, y) => if y == 0 { (bottom: 1pt + accent) } else { (bottom: 0.5pt + gray) },
    [*Area*], [*Perimeter*], [*MajorAxisLength*], [*MinorAxisLength*], [*AspectRation*], [*roundness*], [*Class*],
    [28395], [610,291], [208,178], [173,889], [1,197], [0,958], [SEKER],
    [28734], [638,018], [200,525], [182,734], [1,097], [0,887], [SEKER],
    [29380], [624,110], [212,826], [175,931], [1,210], [0,948], [SEKER],
  ),
  caption: [Trzy przykładowe rekordy ze zbioru Dry Bean.],
)

= Metody analizy

Analizę wykonano w języku Python z użyciem bibliotek `pandas`, `numpy`, `scipy`, `matplotlib`
oraz `seaborn`. Proces analizy obejmował następujące kroki.

== Czyszczenie danych

Napisano funkcję, która sprawdza każdą kolumnę liczbową pod kątem braków (`NaN`), wartości
nieskończonych oraz wartości ujemnych (niemożliwych fizycznie dla pomiarów geometrycznych), a
następnie zastępuje je medianą danej kolumny wyznaczoną z poprawnych wartości. Funkcja
obsługuje też zastępowanie średnią lub losową wartością z zakresu obserwowanego w danych.

```python
def clean_data(
    data_frame: pd.DataFrame,
    numeric_columns: list[str],
    rng: np.random.Generator,
    method: str = "median",
) -> pd.DataFrame:
    cleaned = data_frame.copy()
    for column in numeric_columns:
        series = cleaned[column]
        series = series.replace([np.inf, -np.inf], np.nan)
        series = series.mask(series < 0, np.nan)
        valid = series.dropna()
        n_missing = int(series.isna().sum())
        if method == "mean":
            fill = np.full(n_missing, float(valid.mean()))
        elif method == "random":
            fill = rng.uniform(valid.min(), valid.max(), n_missing)
        else:
            fill = np.full(n_missing, float(valid.median()))
        series.loc[series.isna()] = fill
        cleaned[column] = series
    return cleaned
```

== Statystyki opisowe

Dla każdej zmiennej liczbowej wyznaczono: wartość minimalną i maksymalną, średnią, odchylenie
standardowe (z poprawką `ddof=1`), medianę, kwartyle Q1 i Q3 oraz kwantyle rzędu 0,1 i 0,9.

== Korelacja i regresja

Dla trzech wybranych par zmiennych wyznaczono współczynnik korelacji liniowej Pearsona
($r$) wraz z wartością p, a następnie dopasowano prostą regresję liniową metodą najmniejszych
kwadratów: $y = a dot x + b$, wraz ze współczynnikiem determinacji $R^2$.

```python
def compute_regression(
    x: pd.Series, y: pd.Series
) -> dict[str, float]:
    x_values = x.to_numpy(dtype=float)
    y_values = y.to_numpy(dtype=float)
    regression = linregress(x_values, y_values)
    return {
        "slope": float(regression.slope),
        "intercept": float(regression.intercept),
        "r_squared": float(regression.rvalue) ** 2,
        "p_value": float(regression.pvalue),
    }
```

Pary zmiennych do analizy korelacji i regresji wybrano ręcznie po obejrzeniu macierzy korelacji
całego zbioru: para *Area--Perimeter* reprezentuje korelację silną, para
*Perimeter--roundness* korelację średnią, a para *Area--Extent* korelację bardzo słabą
(praktycznie brak zależności liniowej).

= Wyniki

== Czyszczenie danych

W oryginalnym zbiorze danych nie stwierdzono braków, wartości nieskończonych ani ujemnych
(#dane.czyszczenie.brakujace_wartosci braków, #dane.czyszczenie.wartosci_nieskonczone
nieskończoności, #dane.czyszczenie.wartosci_ujemne wartości ujemnych). Wykryto natomiast
#dane.czyszczenie.duplikaty zduplikowanych wierszy -- są to wiersze identyczne we wszystkich 16
cechach liczbowych, wszystkie należą do jednej klasy: #dane.czyszczenie.duplikaty_klasy. Nie
zostały one usunięte, ponieważ nie są błędem technicznym, tylko realnymi powtórzeniami w
danych źródłowych. Poprawność funkcji czyszczącej zweryfikowano, uruchamiając program z
flagą `--test-cleaning`: na kopii danych wstrzyknięto kilka braków, wartości ujemnych oraz
nieskończonych, po czym funkcja `clean_data` usunęła wszystkie te błędy.

== Liczebność klas

#grid(
  columns: (1fr, 1fr),
  gutter: 1em,
  figure(
    image("dry_bean/output/fig_liczebnosc_kolowy.png", width: 95%),
    caption: [Udział procentowy poszczególnych odmian fasoli.],
  ),
  figure(
    image("dry_bean/output/fig_liczebnosc_slupkowy.png", width: 95%),
    caption: [Liczebność rekordów w poszczególnych klasach.],
  ),
)

Najliczniejszą odmianą jest Dermason (#dane.liczebnosc_klas.DERMASON rekordów), najmniej
liczną -- Bombay (#dane.liczebnosc_klas.BOMBAY rekordów). Klasy są wyraźnie niezbalansowane.

== Statystyki opisowe

#figure(
  text(size: 8.3pt)[
    #table(
      columns: (auto, auto, auto, auto, auto, auto, auto, auto, auto, auto),
      align: (left,) + (right,) * 9,
      inset: 4pt,
      stroke: (x, y) => if y == 0 { (bottom: 1pt + accent) } else { (bottom: 0.5pt + gray) },
      [*Cecha*], [*min*], [*max*], [*średnia*], [*odch. std.*], [*mediana*], [*Q1*], [*Q3*], [*kw. 0,1*], [*kw. 0,9*],
      ..for (nazwa, s) in dane.statystyki_opisowe {
        (
          [#nazwa], [#s.min], [#s.max], [#s.srednia], [#s.odchylenie_std],
          [#s.mediana], [#s.q1], [#s.q3], [#s.kwantyl_0_1], [#s.kwantyl_0_9],
        )
      },
    )
  ],
  caption: [Statystyki opisowe wybranych cech. Pełna tabela dla wszystkich 16 cech znajduje się w pliku #raw("opisowe.csv").],
)

#figure(
  image("dry_bean/output/fig_histogramy.png", width: 92%),
  caption: [Histogramy wybranych cech wraz z estymatą gęstości.],
)

#figure(
  image("dry_bean/output/fig_pudelkowe.png", width: 92%),
  caption: [Wykresy pudełkowe wybranych cech (każda cecha na osobnej skali).],
)

#figure(
  image("dry_bean/output/fig_wiolinowe.png", width: 92%),
  caption: [Wykresy wiolinowe wybranych cech (każda cecha na osobnej skali).],
)

Rozkłady cech geometrycznych (Area, Perimeter) są prawostronnie skośne -- większość ziaren
jest stosunkowo mała, a nieliczne duże ziarna (odmiana Bombay) wydłużają ogon rozkładu. Cecha
`roundness` ma rozkład umiarkowanie lewoskośny, z medianą bliską 0,88 i dłuższym ogonem w
stronę niższych wartości.

== Korelacja i regresja liniowa

#figure(
  table(
    columns: 5,
    stroke: (x, y) => if y == 0 { (bottom: 1pt + accent) } else { (bottom: 0.5pt + gray) },
    [*Para zmiennych*], [*r Pearsona*], [*p-value*], [*Siła związku*], [],
    ..for k in dane.korelacje {
      (
        [#k.zmienna_x -- #k.zmienna_y], [#k.r], [#k.p_value],
        if calc.abs(float(k.r.replace(",", "."))) > 0.7 { [silna] }
          else if calc.abs(float(k.r.replace(",", "."))) > 0.3 { [średnia] }
          else { [słaba] },
        [],
      )
    },
  ),
  caption: [Współczynnik korelacji Pearsona dla trzech wybranych par zmiennych.],
)

#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 0.6em,
  ..dane.regresje.enumerate(start: 1).map(((i, r)) => figure(
    image("dry_bean/output/fig_rozrzut_" + str(i) + ".png", width: 100%),
    caption: [#r.zmienna_x -- #r.zmienna_y: #r.wzor, $R^2=$#r.r2],
  ))
)

Największą zgodność z modelem liniowym obserwujemy dla pary Area--Perimeter ($R^2$ bliskie 1),
co jest zgodne z intuicją geometryczną -- większe ziarno ma zarówno większą powierzchnię, jak i
większy obwód. Para Area--Extent pokazuje natomiast brak praktycznej zależności liniowej.

= Podsumowanie

Przeprowadzona analiza statystyczna pozwoliła poznać podstawowe własności zbioru Dry Bean:
rozkłady poszczególnych cech, siłę zależności między wybranymi parami zmiennych oraz
liczebność poszczególnych odmian fasoli. Dane okazały się kompletne i poprawne (brak błędów
technicznych), a funkcja czyszcząca została pozytywnie zweryfikowana na sztucznie
wprowadzonych błędach. Szeregi czasowe nie dotyczą tego zbioru danych, ponieważ nie zawiera on
żadnej informacji o czasie pomiaru.
