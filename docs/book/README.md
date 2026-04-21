# Bookdown scaffold (R / bookdown)

Tidy starting point for an R + **bookdown** book project.

## Quick start

1. Open `bookdown-scaffold.Rproj` in RStudio.
2. Install dependencies:
   ```r
   install.packages(c("bookdown", "rmarkdown", "knitr"))
   ```
3. Build:
   ```r
   bookdown::render_book("index.Rmd")
   ```

## Layout

- `index.Rmd`: YAML + preface
- `chapters/`: chapters (ordered in `_bookdown.yml`)
- `references/`: BibTeX + CSL
- `assets/`: CSS + images
- `R/`: helper functions
- `data-raw/`: scripts that generate book datasets
- `data/`: small datasets used in examples
- `scripts/`: build helpers
