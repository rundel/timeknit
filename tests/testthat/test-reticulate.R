skip_if_no_python = function() {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("xfun")
  skip_if(xfun::is_R_CMD_check(), "knitr disables progress under R CMD check")
  skip_if_not_installed("reticulate")
  ok = tryCatch(reticulate::py_available(initialize = TRUE), error = function(e) FALSE)
  skip_if_not(isTRUE(ok), "Python is not available to reticulate")
}

mixed_doc = c(
  "```{r setup}", "library(reticulate)", "x = 1:3", "```", "",
  "```{python}", "#| label: py-square", "#| echo: false", "sq = [v ** 2 for v in r.x]", "```", "",
  "```{r back}", "cat(unlist(py$sq))", "```", "",
  "```{python}", "print(sum(sq))", "```"
)

test_that("python chunks run through reticulate are timed and recorded like R chunks", {
  skip_if_no_python()

  dir = tempfile("py")
  dir.create(dir)
  file = knit_file(mixed_doc, dir)
  op = options(knitr.progress.fun = knit_progress, timeknit.record = TRUE)
  on.exit(options(op))
  out = knit_quietly(file)

  expect_match(out, "^3/7 \\[py-square\\]        [0-9.]+ (µs|us|ms|s)$", all = FALSE)
  expect_match(out, "^7/7 \\[unnamed-chunk-1\\]  [0-9.]+ (µs|us|ms|s)$", all = FALSE)
  expect_match(out, "^Total chunk time: .* \\(4 chunks\\)$", all = FALSE)

  rendered = readLines(paste0(file, ".md"))
  expect_true(any(grepl("## 1 4 9", rendered, fixed = TRUE)))
  expect_true(any(grepl("## 14", rendered, fixed = TRUE)))

  json = jsonlite::fromJSON(file.path(dir, ".quarto", "timeknit", "doc.Rmd.json"))
  expect_equal(json$status, "complete")
  expect_equal(json$chunks$label, c("setup", "py-square", "back", "unnamed-chunk-1"))
  expect_equal(json$chunks$start, c(1L, 6L, 12L, 16L))
  expect_equal(json$chunks$end, c(4L, 10L, 14L, 18L))
  expect_equal(
    json$chunks$code,
    c("library(reticulate)\nx = 1:3", "sq = [v ** 2 for v in r.x]", "cat(unlist(py$sq))", "print(sum(sq))")
  )
  expect_true(all(json$chunks$elapsed > 0))
})

test_that("an error raised in a python chunk is recorded with its label", {
  skip_if_no_python()

  dir = tempfile("py")
  dir.create(dir)
  file = knit_file(
    c("```{python py-ok}", "y = 1", "```", "", "```{python py-boom}", "raise ValueError('no')", "```", "", "```{r never}", "2", "```"),
    dir
  )
  op = options(knitr.progress.fun = knit_progress, timeknit.record = TRUE)
  on.exit(options(op))
  old_error = knitr::opts_chunk$get("error")
  knitr::opts_chunk$set(error = FALSE)
  on.exit(knitr::opts_chunk$set(error = old_error), add = TRUE)
  expect_error(knit_quietly(file), "ValueError")

  json = jsonlite::fromJSON(file.path(dir, ".quarto", "timeknit", "doc.Rmd.json"))
  expect_equal(json$status, "error")
  expect_equal(json$failed, "py-boom")
  expect_equal(json$chunks$label, c("py-ok", "py-boom"))
})
