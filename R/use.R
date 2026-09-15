#' Register timeknit's progress display with knitr
#'
#' Sets the `knitr.progress.fun` option so that knitr, and therefore Quarto
#' documents rendered with the knitr engine, use [knit_progress()]. The usual
#' place to call it is your `.Rprofile`, either the one in your home directory
#' or a project specific one next to the documents you render:
#'
#' ```r
#' if (requireNamespace("timeknit", quietly = TRUE)) timeknit::use_timeknit()
#' ```
#'
#' @return The previous value of the `knitr.progress.fun` option, invisibly, in
#'   a form that can be passed back to `options()` to restore it.
#' @export
use_timeknit = function() {
  invisible(options(knitr.progress.fun = knit_progress))
}
