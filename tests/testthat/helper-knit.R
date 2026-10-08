knit_file = function(lines, dir, name = "doc.Rmd") {
  file = file.path(dir, name)
  writeLines(lines, file)
  file
}

knit_quietly = function(file) {
  out = NULL
  capture.output(type = "message", {
    out = suppressMessages(capture.output(
      knitr::knit(file, output = paste0(file, ".md"), envir = new.env(parent = globalenv()), quiet = FALSE)
    ))
  })
  invisible(out)
}
