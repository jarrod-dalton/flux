# CSS themes

This folder contains multiple CSS themes you can try.

## How to switch themes

Open `assets/style.css` and uncomment **exactly one** `@import` line, e.g.

```css
@import url("themes/theme-01-ink-and-saffron.css");
```

Then rebuild:

```r
bookdown::render_book("index.Rmd")
```

## Themes included

1. theme-01-ink-and-saffron (warm accents, serif body)
2. theme-02-midnight-lab (dark, high-contrast)
3. theme-03-sea-glass (cool, airy)
4. theme-04-copper-and-ash (editorial)
5. theme-05-forest-notes (warm paper + green accents)
6. theme-06-royal-margin (purple hierarchy)
7. theme-07-paperback-warm (cozy paperback)
8. theme-08-solarized-ish (balanced contrast)
9. theme-09-quiet-neon (modern accents, dark code blocks)
10. theme-10-minimal-serif (classic serif + crisp headings)
