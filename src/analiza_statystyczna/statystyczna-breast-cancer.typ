#let dane = json("breast_cancer_wisconsin/output/results.json")

#set page(margin: (x: 1.8cm, y: 1.8cm))
#set text(font: "Liberation Sans", size: 10pt, lang: "pl")
#set par(justify: false)
#set heading(numbering: "1.")
#show raw: set text(font: "Liberation Mono", size: 9pt)
#show raw.where(block: true): it => block(
  fill: luma(245), inset: 8pt, radius: 2pt, width: 100%, breakable: false, it,
)
#show table.cell.where(y: 0): set text(weight: "bold")
#set table(stroke: 0.6pt + gray)

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

#v(0.3em)
#text(size: 13pt, weight: "bold")[Breast Cancer Wisconsin (Diagnostic) -- sprawozdanie ze statystycznej analizy danych]

#line(length: 100%, stroke: 0.6pt)

= Dane w skrócie

- Zbiór: Breast Cancer Wisconsin (Diagnostic), UCI id=17.
- Liczba rekordów: #dane.liczba_rekordow, liczba cech liczbowych: #dane.liczba_cech.
- Klasa: `diagnosis`, dwie wartości: B (benign, łagodny) / M (malignant, złośliwy).
- Źródło: University of Wisconsin, 1995, pomiary z obrazu cyfrowego biopsji aspiracyjnej
  (fine needle aspirate) guza piersi.
- Kolumnę `id` usunięto -- nie niesie informacji statystycznej.

= Atrybuty i przykładowe rekordy

Dla każdego obrazu wyznaczono 10 podstawowych wielkości geometrycznych i teksturowych, a każdą
z nich zapisano trzykrotnie: jako wartość średnią (`_mean`), błąd standardowy (`_se`) oraz
wartość najgorszą/najwyższą (`_worst`) -- razem 30 cech.

#figure(
  table(
    columns: (auto, 1fr),
    [*Wielkość*], [*Znaczenie*],
    [radius], [średni promień konturu jądra komórkowego],
    [texture], [odchylenie standardowe wartości w skali szarości],
    [perimeter], [obwód konturu jądra],
    [area], [powierzchnia jądra],
    [smoothness], [lokalna zmienność długości radiusów (gładkość konturu)],
    [compactness], [zwartość konturu, $P^2 \/ A - 1$],
    [concavity], [głębokość wklęsłych odcinków konturu],
    [concave points], [liczba wklęsłych punktów konturu],
    [symmetry], [symetria jądra],
    [fractal dimension], [wymiar fraktalny konturu],
  ),
  caption: [Znaczenie dziesięciu podstawowych wielkości (opracowano na podstawie pliku `wdbc.names`).],
)

#figure(
  table(
    columns: 6,
    [*radius\_mean*], [*texture\_mean*], [*perimeter\_mean*], [*area\_mean*], [*smoothness\_mean*], [*diagnosis*],
    ..for r in dane.przykladowe_rekordy {
      (
        [#r.radius_mean], [#r.texture_mean], [#r.perimeter_mean],
        [#r.area_mean], [#r.smoothness_mean], [#r.diagnosis],
      )
    },
  ),
  caption: [Trzy przykładowe rekordy ze zbioru (wybrane kolumny).],
)

= Wyniki czyszczenia danych

- Braki (`NaN`): #dane.czyszczenie.brakujace_wartosci
- Wartości nieskończone: #dane.czyszczenie.wartosci_nieskonczone
- Wartości ujemne (niemożliwe dla tych pomiarów): #dane.czyszczenie.wartosci_ujemne
- Zduplikowane wiersze: #dane.czyszczenie.duplikaty
- Wniosek: dane wejściowe są kompletne i poprawne, funkcja czyszcząca nie musiała nic
  naprawiać. Jej działanie zweryfikowano osobno flagą `--test-cleaning`, która na kopii danych
  wstrzykuje braki, wartości ujemne i nieskończone, a następnie pokazuje, że po czyszczeniu
  wszystkie te błędy znikają.

= Liczebność klas

#grid(
  columns: (1fr, 1fr),
  gutter: 0.8em,
  figure(
    image("breast_cancer_wisconsin/output/fig_liczebnosc_kolowy.png", width: 95%),
    caption: [Udział klas B/M.],
  ),
  figure(
    image("breast_cancer_wisconsin/output/fig_liczebnosc_slupkowy.png", width: 95%),
    caption: [Liczba rekordów na klasę.],
  ),
)

- B (łagodny): #dane.liczebnosc_klas.B rekordów
- M (złośliwy): #dane.liczebnosc_klas.M rekordów
- Klasy są umiarkowanie niezbalansowane (ok. 63% / 37%).

= Statystyki opisowe (wybrane cechy)

#figure(
  text(size: 8.3pt)[
    #table(
      columns: (auto, auto, auto, auto, auto, auto, auto, auto, auto, auto),
      align: (left,) + (right,) * 9,
      inset: 4pt,
      [*cecha*], [*min*], [*max*], [*średnia*], [*odch. std.*], [*mediana*], [*Q1*], [*Q3*], [*kw. 0,1*], [*kw. 0,9*],
      ..for (nazwa, s) in dane.statystyki_opisowe {
        (
          [#nazwa], [#s.min], [#s.max], [#s.srednia], [#s.odchylenie_std],
          [#s.mediana], [#s.q1], [#s.q3], [#s.kwantyl_0_1], [#s.kwantyl_0_9],
        )
      },
    )
  ],
  caption: [Statystyki pięciu wybranych cech. Pełna tabela dla wszystkich 30 cech: plik `opisowe.csv`.],
)

= Korelacja Pearsona i regresja liniowa

Wzięto trzy pary zmiennych, żeby pokazać silną, średnią i słabą korelację:
- `radius_mean`–`perimeter_mean`: silna (obwód wynika z promienia),
- `smoothness_mean`–`fractal_dimension_mean`: średnia,
- `texture_mean`–`smoothness_mean`: praktycznie zerowa.

#figure(
  table(
    columns: 4,
    [*para zmiennych*], [*r Pearsona*], [*p-value*], [*wzór regresji*],
    ..for (k, r) in dane.korelacje.zip(dane.regresje) {
      ([#k.zmienna_x -- #k.zmienna_y], [#k.r], [#k.p_value], [#r.wzor])
    },
  ),
  caption: [Korelacja i regresja liniowa dla trzech wybranych par zmiennych.],
)

#grid(
  columns: (1fr, 1fr, 1fr),
  gutter: 0.6em,
  ..dane.regresje.enumerate(start: 1).map(((i, r)) => figure(
    image("breast_cancer_wisconsin/output/fig_rozrzut_" + str(i) + ".png", width: 100%),
    caption: [#r.zmienna_x vs #r.zmienna_y: $R^2=$#r.r2],
  ))
)

- Para radius_mean--perimeter_mean: $R^2$ bliskie 1 -- promień i obwód niosą praktycznie tę
  samą informację (co wynika z geometrii koła/elipsy).
- Para smoothness_mean--fractal_dimension_mean: zależność umiarkowana, dodatnia.
- Para texture_mean--smoothness_mean: brak zależności liniowej, punkty na wykresie tworzą
  "chmurę" bez widocznego trendu.

= Rozkłady wybranych cech

#figure(
  image("breast_cancer_wisconsin/output/fig_histogramy.png", width: 92%),
  caption: [Histogramy pięciu wybranych cech.],
)

#figure(
  image("breast_cancer_wisconsin/output/fig_pudelkowe.png", width: 92%),
  caption: [Wykresy pudełkowe (każda cecha na osobnej skali, widoczne wartości odstające).],
)

#figure(
  image("breast_cancer_wisconsin/output/fig_wiolinowe.png", width: 92%),
  caption: [Wykresy wiolinowe -- kształt rozkładu każdej cechy.],
)

- `radius_mean`, `texture_mean`, `perimeter_mean` mają rozkład prawostronnie skośny -- większość
  guzów jest mała/średnia, a nieliczne duże obserwacje wydłużają ogon. Średni `radius_mean`
  w klasie M (złośliwy) to #dane.srednie_wg_klasy.radius_mean.M, a w klasie B (łagodny) --
  #dane.srednie_wg_klasy.radius_mean.B, więc duże wartości w ogonie rozkładu należą głównie do
  guzów złośliwych.
- `concavity_mean` ma dużo wartości bliskich zeru i długi ogon po prawej -- wiele guzów ma
  niewielką wklęsłość konturu.
- `smoothness_mean` jest rozkładem najbardziej zbliżonym do symetrycznego spośród pięciu
  analizowanych cech.

= Metody i kod

Czyszczenie, statystyki, korelację i regresję policzono w Pythonie (`pandas`, `numpy`,
`scipy.stats.pearsonr`, `scipy.stats.linregress`). Wykresy: `matplotlib` + `seaborn`.

Funkcja wykrywająca i naprawiająca błędy (braki/`inf`/wartości ujemne) zastępuje je medianą
kolumny policzoną z poprawnych wartości (obsługuje też tryb ze średnią i z losową wartością z
zaobserwowanego zakresu):

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

Regresja liniowa $y = a dot x + b$ wraz z $R^2$ i p-value:

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

= Wnioski

- Dane wejściowe nie wymagały napraw -- zero braków, wartości ujemnych i duplikatów.
- Klasy B/M są niezbalansowane (63%/37%), co trzeba by uwzględnić na etapie eksploracyjnym
  (poza zakresem tego sprawozdania).
- `radius_mean` i `perimeter_mean` są praktycznie równoważne informacyjnie -- do dalszej
  analizy wystarczy jedna z tych dwóch cech.
- Analiza szeregów czasowych nie dotyczy tego zbioru -- dane nie zawierają znacznika czasu,
  każdy rekord to pojedynczy, niezależny pomiar.

= Wzory

*Statystyki opisowe* (dla każdej cechy):
- średnia: $overline(x) = 1/n sum_(i=1)^n x_i$
- odchylenie standardowe: $s = sqrt(1/(n-1) sum_(i=1)^n (x_i - overline(x))^2)$
- mediana: wartość środkowa po posortowaniu danych
- kwantyl rzędu $p$: wartość, poniżej której leży $p dot 100%$ danych; Q1 to $p = "0,25"$, Q3 to $p = "0,75"$, a kwantyle 0,1 i 0,9 to $p = "0,1"$ i $p = "0,9"$

#let cov = math.op("cov")

*Korelacja Pearsona:* $r = cov(x, y) / (s_x dot s_y)$, gdzie $cov(x, y) = 1/(n-1) sum_(i=1)^n (x_i - overline(x))(y_i - overline(y))$. Wynik jest z przedziału od $-1$ do $1$.

*Regresja liniowa:* $hat(y) = a dot x + b$, gdzie $a = cov(x, y) / s_x^2$ oraz $b = overline(y) - a dot overline(x)$. Współczynnik determinacji: $R^2 = r^2$.

*Uzupełnianie braków:* $x_i := "mediana"(x_"poprawne")$ -- mediana liczona tylko z poprawnych wartości kolumny.

*Przykład z naszych danych* (`radius_mean` i `perimeter_mean`): $r = "0,998"$, $R^2 = "0,996"$, wzór regresji: $y = "6,8804" dot x - "5,2324"$.

#table(
  columns: (auto, 1fr),
  align: left,
  table.header[*Symbol*][*Znaczenie*],
  [$n$], [liczba rekordów (u nas 569)],
  [$x_i, y_i$], [$i$-ta wartość zmiennej $x$ i zmiennej $y$],
  [$overline(x), overline(y)$], [średnie zmiennych $x$ i $y$],
  [$s, s_x$], [odchylenie standardowe (ogólne i zmiennej $x$)],
  [$p$], [rząd kwantyla (liczba od 0 do 1)],
  [$cov(x, y)$], [kowariancja: czy $x$ i $y$ odchylają się od średnich w tę samą stronę],
  [$r$], [współczynnik korelacji Pearsona],
  [$a, b$], [nachylenie i wyraz wolny prostej regresji],
  [$hat(y)$], [wartość $y$ przewidziana przez prostą],
  [$R^2$], [jaką część zmienności $y$ tłumaczy prosta (od 0 do 1)],
)

