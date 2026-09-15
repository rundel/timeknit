test_that("format_duration picks units by magnitude", {
  us = timeknit:::micro_sign()
  expect_equal(format_duration(0), paste0("0 ", us, "s"))
  expect_equal(format_duration(1.23456e-5), paste0("12.3 ", us, "s"))
  expect_equal(format_duration(0.0456), "45.6 ms")
  expect_equal(format_duration(0.123456), "123 ms")
  expect_equal(format_duration(0.9996), "1 s")
  expect_equal(format_duration(1.234), "1.23 s")
  expect_equal(format_duration(45.678), "45.7 s")
  expect_equal(format_duration(75), "1m 15s")
  expect_equal(format_duration(4000), "1h 6m 40s")
})

test_that("format_duration is vectorised and handles NA", {
  expect_equal(format_duration(c(0.5, NA, 2)), c("500 ms", NA, "2 s"))
  expect_equal(format_duration(numeric(0)), character(0))
})
