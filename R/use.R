#' Register timeknit's progress display with knitr
#'
#' Sets the `knitr.progress.fun` option so that knitr, and therefore Quarto
#' documents rendered with the knitr engine, use [knit_progress()]. It only
#' affects the current R session; to make a project use it every time, see
#' [use_timeknit_project()], which puts the call into the project's profile.
#' If you prefer a global setup, add the following to `~/.Rprofile` yourself:
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
