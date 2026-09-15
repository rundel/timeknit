run_progress = function(labels, steps, ...) {
  op = options(timeknit.record = FALSE, ...)
  on.exit(options(op))
  capture.output({
    pb = knit_progress(length(labels), labels)
    for (step in steps) step(pb)
  })
}

test_that("chunk lines get a timing and text lines do not", {
  out = run_progress(
    c("", "setup", "", "slow"),
    list(
      function(pb) pb$update(1),
      function(pb) pb$update(2),
      function(pb) pb$update(3),
      function(pb) { pb$update(4); Sys.sleep(0.05) },
      function(pb) pb$done()
    )
  )
  expect_equal(out[1], "1/4        ")
  expect_match(out[2], "^2/4 \\[setup\\]  [0-9.]+ (µ|u|m)s$")
  expect_equal(out[3], "3/4        ")
  expect_match(out[4], "^4/4 \\[slow\\]   [0-9.]+ ms$")
  expect_match(out[5], "^Total chunk time: .* \\(2 chunks\\)$")
  expect_equal(out[6], "Slowest chunks:")
  expect_match(out[7], "^  \\[slow\\]   [0-9.]+ ms$")
  expect_match(out[8], "^  \\[setup\\]  ")
  expect_length(out, 8)
})

test_that("block numbers are right aligned to the total", {
  labels = c(rep("", 9), "ten")
  out = run_progress(labels, list(function(pb) for (i in 1:10) pb$update(i), function(pb) pb$done()))
  expect_equal(out[1], " 1/10      ")
  expect_match(out[10], "^10/10 \\[ten\\]  ")
})

test_that("interrupt writes the timing to the message stream and skips the summary", {
  err = capture.output(type = "message", {
    out = run_progress(
      c("", "boom"),
      list(function(pb) pb$update(1), function(pb) pb$update(2), function(pb) pb$interrupt(), function(pb) pb$done())
    )
  })
  expect_equal(out, c("1/2       ", "2/2 [boom]"))
  expect_match(err, "^  [0-9.]+ (µ|u|m)s$")
  expect_length(err, 1)
})

test_that("options control text blocks, the summary, and the slowest list", {
  steps = list(function(pb) for (i in 1:3) pb$update(i), function(pb) pb$done())
  labels = c("", "a", "b")

  out = run_progress(labels, steps, timeknit.text_blocks = FALSE)
  expect_match(out[1], "^2/3 \\[a\\]")
  expect_match(out[2], "^3/3 \\[b\\]")

  out = run_progress(labels, steps, timeknit.summary = FALSE)
  expect_length(out, 3)

  out = run_progress(labels, steps, timeknit.slowest = 1)
  expect_length(out, 6)
  expect_equal(out[5], "Slowest chunk:")

  out = run_progress(labels, steps, timeknit.slowest = 0)
  expect_length(out, 4)
})

test_that("a connection from knitr.progress.output receives all output", {
  con = textConnection("captured", "w", local = TRUE)
  op = options(knitr.progress.output = con)
  on.exit({ options(op); close(con) })
  err = capture.output(type = "message", {
    pb = knit_progress(1, "x")
    pb$update(1)
    pb$interrupt()
    pb$done()
  })
  expect_length(err, 0)
  expect_match(captured, "^1/1 \\[x\\]  [0-9.]+ (µ|u|m)s$")
})

test_that("nested displays are indented, skip the summary, and repeat the parent line", {
  op = options(timeknit.record = FALSE)
  on.exit(options(op))
  out = capture.output({
    parent = knit_progress(2, c("outer", ""))
    parent$update(1)
    cat("\n")
    child = knit_progress(2, c("inner", ""))
    child$update(1)
    child$update(2)
    child$done()
    parent$update(2)
    parent$done()
  })
  expect_equal(out[1], "1/2 [outer]")
  expect_match(out[2], "^  1/2 \\[inner\\]  [0-9.]+ (µ|u|m)s$")
  expect_equal(out[3], "  2/2        ")
  expect_match(out[4], "^1/2 \\[outer\\]  [0-9.]+ (µ|u|m)s$")
  expect_equal(out[5], "2/2        ")
  expect_match(out[6], "^Total chunk time: .* \\(1 chunk\\)$")
  expect_length(out, 8)
  expect_length(timeknit:::.state$bars, 0)
})

test_that("filename output retains every line, nested output, and error timing", {
  file = tempfile()
  writeLines("Earlier output", file)
  op = options(knitr.progress.output = file)
  on.exit(options(op))
  parent = knit_progress(2, c("outer", "last"))
  parent$update(1)
  cat("\n", file = file, append = TRUE)
  child = knit_progress(1, "inner")
  child$update(1)
  child$done()
  parent$update(2)
  parent$done()
  output = readLines(file)
  expect_equal(output[1:2], c("Earlier output", "1/2 [outer]"))
  expect_match(output[3], "^  1/1 \\[inner\\]  .+s$")
  expect_match(output[4], "^1/2 \\[outer\\]  .+s$")
  expect_match(output[5], "^2/2 \\[last\\]   .+s$")
  expect_match(output[6], "^Total chunk time: .* \\(2 chunks\\)$")
  expect_equal(output[7], "Slowest chunks:")
  expect_length(output, 9)
  pb = knit_progress(1, "boom")
  pb$update(1)
  pb$interrupt()
  pb$done()
  expect_equal(readLines(file)[seq_along(output)], output)
  expect_match(tail(readLines(file), 1), "^1/1 \\[boom\\]  .+s$")
  expect_length(readLines(file), 10)
})

test_that("knitr picks the display up through knitr.progress.fun", {
  skip_if_not_installed("xfun")
  skip_if(xfun::is_R_CMD_check(), "knitr disables progress under R CMD check")

  op = options(knitr.progress.fun = knit_progress, timeknit.record = FALSE)
  on.exit(options(op))
  src = c("Some text", "", "```{r wait}", "Sys.sleep(0.02)", "```", "", "More text")
  out = capture.output({
    res = knitr::knit(text = src, envir = new.env(), quiet = FALSE)
  })

  expect_match(out[2], "^2/3 \\[wait\\]  [0-9.]+ ms$")
  expect_match(out[4], "^Total chunk time: .* \\(1 chunk\\)$")
  expect_match(res, "Sys.sleep", all = FALSE)
})
