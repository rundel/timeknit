knit_file = function(lines, dir, name = "doc.Rmd") {
  file = file.path(dir, name)
  writeLines(lines, file)
  file
}

knit_quietly = function(file) {
  out = NULL
  capture.output(type = "message", {
    out = suppressMessages(capture.output(
      knitr::knit(file, output = paste0(file, ".md"), envir = new.env(), quiet = FALSE)
    ))
  })
  invisible(out)
}

sample_doc = c(
  "Text", "",
  "```{r setup}", "x = 1", "```", "",
  "```{r}", "#| label: model", "Sys.sleep(0.02)", "```", "",
  "```{r}", "z = 3", "```"
)

test_that("json helpers escape and format values", {
  expect_equal(json_string("a\"b\\c\nd\te"), "\"a\\\"b\\\\c\\nd\\te\"")
  expect_equal(json_string(NA_character_), "null")
  expect_equal(json_string(paste0("x", intToUtf8(1))), "\"x\\u0001\"")
  expect_equal(json_number(0.0042), "0.0042")
  expect_equal(json_number(7L), "7")
  expect_equal(json_number(NA_real_), "null")
  expect_equal(json_object(list(a = json_number(1), b = json_string("s"))), "{\"a\":1,\"b\":\"s\"}")
})

test_that("relative_path falls back to the basename outside the root", {
  expect_equal(relative_path("/root/a/b.qmd", "/root"), "a/b.qmd")
  expect_equal(relative_path("/root/a/b.qmd", "/root/"), "a/b.qmd")
  expect_equal(relative_path("/elsewhere/b.qmd", "/root"), "b.qmd")
})

test_that("a timing record is written next to the document", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("xfun")
  skip_if(xfun::is_R_CMD_check(), "knitr disables progress under R CMD check")

  dir = tempfile("rec")
  dir.create(dir)
  file = knit_file(sample_doc, dir)
  op = options(knitr.progress.fun = knit_progress, timeknit.record = TRUE)
  on.exit(options(op))
  knit_quietly(file)

  record = file.path(dir, ".quarto", "timeknit", "doc.Rmd.json")
  expect_true(file.exists(record))
  json = jsonlite::fromJSON(record)
  expect_equal(json$version, 1)
  expect_equal(json$status, "complete")
  expect_null(json$failed)
  expect_equal(json$file, normalizePath(file))
  expect_equal(json$relative, "doc.Rmd")
  expect_equal(json$chunks$label, c("setup", "model", "unnamed-chunk-1"))
  expect_equal(json$chunks$start, c(3L, 7L, 12L))
  expect_equal(json$chunks$end, c(5L, 10L, 14L))
  expect_equal(json$chunks$code, c("x = 1", "Sys.sleep(0.02)", "z = 3"))
  expect_true(all(json$chunks$elapsed > 0))
  expect_equal(json$total, sum(json$chunks$elapsed))
  expect_match(json$time, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
})

test_that("an erroring chunk is recorded with status error", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("xfun")
  skip_if(xfun::is_R_CMD_check(), "knitr disables progress under R CMD check")

  dir = tempfile("rec")
  dir.create(dir)
  file = knit_file(c("```{r ok}", "1", "```", "", "```{r boom}", "stop('no')", "```", "", "```{r never}", "2", "```"), dir)
  op = options(knitr.progress.fun = knit_progress, timeknit.record = TRUE)
  on.exit(options(op))
  old_error = knitr::opts_chunk$get("error")
  knitr::opts_chunk$set(error = FALSE)
  on.exit(knitr::opts_chunk$set(error = old_error), add = TRUE)
  expect_error(knit_quietly(file))

  json = jsonlite::fromJSON(file.path(dir, ".quarto", "timeknit", "doc.Rmd.json"))
  expect_equal(json$status, "error")
  expect_equal(json$failed, "boom")
  expect_equal(json$chunks$label, c("ok", "boom"))
})

test_that("the record option can disable or redirect recording", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("xfun")
  skip_if(xfun::is_R_CMD_check(), "knitr disables progress under R CMD check")

  dir = tempfile("rec")
  dir.create(dir)
  file = knit_file(sample_doc, dir)

  op = options(knitr.progress.fun = knit_progress, timeknit.record = FALSE)
  on.exit(options(op))
  knit_quietly(file)
  expect_false(dir.exists(file.path(dir, ".quarto")))

  other = tempfile("records")
  options(timeknit.record = other)
  knit_quietly(file)
  expect_true(file.exists(file.path(other, "doc.Rmd.json")))
  expect_false(dir.exists(file.path(dir, ".quarto")))
})
