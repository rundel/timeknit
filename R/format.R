#' Format durations with human friendly units
#'
#' Chooses microseconds, milliseconds, seconds, or minutes and seconds based on
#' the size of each duration, and rounds to three significant digits.
#'
#' @param secs A numeric vector of durations in seconds.
#' @return A character vector the same length as `secs`.
#' @examples
#' format_duration(c(0.0000123, 0.0456, 1.234, 75, 4000))
#' @export
format_duration = function(secs) {
  vapply(secs, format_duration_one, character(1), USE.NAMES = FALSE)
}

format_duration_one = function(secs) {
  if (is.na(secs)) return(NA_character_)
  secs = signif(secs, 3)
  if (secs < 1e-3) return(paste0(fmt_num(secs * 1e6), " ", micro_sign(), "s"))
  if (secs < 1) return(paste0(fmt_num(secs * 1e3), " ms"))
  if (secs < 60) return(paste0(fmt_num(secs), " s"))

  mins = floor(secs / 60)
  rem = round(secs - mins * 60)
  if (secs < 3600) return(paste0(mins, "m ", rem, "s"))

  hours = floor(mins / 60)
  paste0(hours, "h ", mins - hours * 60, "m ", rem, "s")
}

fmt_num = function(x) {
  format(x, trim = TRUE, scientific = FALSE, drop0trailing = TRUE)
}

micro_sign = function() {
  if (isTRUE(l10n_info()[["UTF-8"]])) "\u00b5" else "u"
}
