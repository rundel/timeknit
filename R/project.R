#' Set up a project to report chunk times
#'
#' Configures a project so that knitr and Quarto renders started from it use
#' timeknit, without touching `~/.Rprofile` or the site-wide profiles.
#'
#' `use_timeknit_project()` makes these changes at the project root:
#'
#' * Adds a managed block to the project's `.Rprofile`, creating the file if
#'   needed, that calls [use_timeknit()]. This covers R sessions started in the
#'   project, `rmarkdown::render()` and `knitr::knit()` from those sessions, and
#'   Quarto renders of documents in the project root. When the file is created
#'   from scratch the block also sources `~/.Rprofile` first, because a project
#'   `.Rprofile` otherwise replaces it.
#' * In a Quarto project (one with `_quarto.yml`), also writes a
#'   `.timeknit.Rprofile` and points `R_PROFILE_USER` at it from
#'   `_environment.local`. Quarto starts R in each document's own directory,
#'   where the project `.Rprofile` is not read, so this is what reaches
#'   documents in subdirectories. The profile loads whatever profile R would
#'   otherwise have used and then activates timeknit. `_environment.local`
#'   holds an absolute path, so in a git repository it is added to
#'   `.gitignore`.
#'
#' Existing `R_PROFILE_USER` assignments in `_environment.local` are saved as
#' comments and restored on removal. The generated profile first sources the
#' previously configured profile from `_environment.local` or `_environment`,
#' if any. Duplicate assignments are preserved, with the last one taking effect.
#'
#' `remove_timeknit_project()` reverses all of this, leaving other content of
#' those files untouched and deleting files that end up empty.
#'
#' @param path The project root, or any directory inside it. The root is the
#'   nearest directory at or above `path` containing `_quarto.yml`, an
#'   `.Rproj` file, `DESCRIPTION`, or `.git`, falling back to `path` itself.
#' @return The project root, invisibly.
#' @seealso [sitrep()] to check the result.
#' @export
use_timeknit_project = function(path = ".") {
  root = find_root(path)
  cli::cli_alert_info("Project root: {.path {root}}")

  update_rprofile(root)
  if (is_quarto_project(root)) {
    write_profile(root, original_profile_user(root))
    update_environment_local(root)
    update_gitignore(root)
  } else if (length(find_documents(root, subdirs_only = TRUE))) {
    cli::cli_alert_warning(paste0(
      "Documents in subdirectories are not reached by {.path .Rprofile} when rendered with ",
      "{.code quarto render}; add a {.path _quarto.yml} and rerun to cover them"
    ))
  }

  use_timeknit()
  cli::cli_alert_success("timeknit is active in this session")
  cli::cli_alert_info("Run {.run timeknit::sitrep()} to review the setup")
  invisible(root)
}

#' @rdname use_timeknit_project
#' @export
remove_timeknit_project = function(path = ".") {
  root = find_root(path)
  cli::cli_alert_info("Project root: {.path {root}}")

  changed = remove_rprofile_block(root)
  changed = remove_profile(root) || changed
  changed = remove_environment_local(root) || changed
  if (!changed) cli::cli_alert_info("Nothing to remove")
  invisible(root)
}

block_start = "# >>> timeknit >>>"
block_end = "# <<< timeknit <<<"
profile_name = ".timeknit.Rprofile"
env_local_name = "_environment.local"
managed_note = "# Managed by timeknit::use_timeknit_project(); remove with timeknit::remove_timeknit_project()."
activation_line = 'if (requireNamespace("timeknit", quietly = TRUE)) timeknit::use_timeknit()'
saved_profile_prefix = "# timeknit saved R_PROFILE_USER: "

find_root = function(path = ".") {
  if (!dir.exists(path)) cli::cli_abort("{.path {path}} is not a directory")
  path = normalizePath(path)
  dir = path
  repeat {
    if (!is.null(root_marker(dir))) return(dir)
    parent = dirname(dir)
    if (identical(parent, dir)) return(path)
    dir = parent
  }
}

root_marker = function(dir) {
  markers = c("_quarto.yml", "_quarto.yaml", "DESCRIPTION", ".git")
  hit = markers[file.exists(file.path(dir, markers))]
  if (length(hit)) return(hit[1])
  rproj = list.files(dir, pattern = "\\.Rproj$")
  if (length(rproj)) rproj[1] else NULL
}

is_quarto_project = function(root) {
  any(file.exists(file.path(root, c("_quarto.yml", "_quarto.yaml"))))
}

in_git_repo = function(dir) {
  repeat {
    if (file.exists(file.path(dir, ".git"))) return(TRUE)
    parent = dirname(dir)
    if (identical(parent, dir)) return(FALSE)
    dir = parent
  }
}

user_profile_path = function() {
  path.expand("~/.Rprofile")
}

env_profile_user = function() {
  value = Sys.getenv("R_PROFILE_USER", unset = NA)
  if (is.na(value) || !nzchar(value)) NA_character_ else value
}

read_lines = function(file) {
  readLines(file, warn = FALSE, encoding = "UTF-8")
}

write_lines = function(lines, file) {
  writeLines(enc2utf8(lines), file, useBytes = TRUE)
}

strip_comments = function(lines) {
  sub("#.*$", "", lines)
}

activates_timeknit = function(lines) {
  exprs = tryCatch(parse(text = lines), error = function(e) expression())
  is_reference = function(x, name) {
    identical(x, as.name(name)) ||
      (is.call(x) && length(x) == 3L &&
       identical(x[[1]], as.name("::")) &&
       identical(x[[2]], as.name("timeknit")) &&
       identical(x[[3]], as.name(name)))
  }
  progress_value = function(x) {
    if (is_reference(x, "knit_progress")) return(TRUE)
    if (!is.call(x)) return(FALSE)
    if (identical(x[[1]], as.name("::")) || identical(x[[1]], as.name(":::"))) return(FALSE)
    if (is_reference(x[[1]], "knit_progress")) return(TRUE)
    any(vapply(as.list(x)[-1], progress_value, logical(1)))
  }
  activates = function(x) {
    if (!is.call(x)) return(FALSE)
    if (is_reference(x[[1]], "use_timeknit")) return(TRUE)
    # Defining a function does not execute its body.
    if (identical(x[[1]], as.name("function"))) return(FALSE)
    args = as.list(x)[-1]
    if (identical(x[[1]], as.name("options"))) {
      i = which(names(args) == "knitr.progress.fun")
      if (length(i) && any(vapply(args[i], progress_value, logical(1)))) return(TRUE)
    }
    any(vapply(args, activates, logical(1)))
  }
  any(vapply(as.list(exprs), activates, logical(1)))
}

sources_user_profile = function(lines) {
  any(grepl("source\\(\\s*[\"']~/\\.Rprofile[\"']", strip_comments(lines)))
}

has_block = function(lines) {
  any(lines == block_start) && any(lines == block_end)
}

rprofile_block = function(new_file) {
  c(
    block_start,
    managed_note,
    if (new_file) c(
      "# A project .Rprofile replaces ~/.Rprofile, so load that first.",
      'if (file.exists("~/.Rprofile")) source("~/.Rprofile")'
    ),
    activation_line,
    block_end
  )
}

update_rprofile = function(root) {
  file = file.path(root, ".Rprofile")
  exists = file.exists(file)
  lines = if (exists) read_lines(file) else character()

  if (has_block(lines)) {
    cli::cli_alert_success("{.path .Rprofile} already has the timeknit block")
    return(invisible(FALSE))
  }
  if (activates_timeknit(lines)) {
    cli::cli_alert_success("{.path .Rprofile} already activates timeknit")
    return(invisible(FALSE))
  }

  separator = if (length(lines) && nzchar(trimws(lines[length(lines)]))) ""
  write_lines(c(lines, separator, rprofile_block(!exists)), file)
  if (exists) {
    cli::cli_alert_success("Adding the timeknit block to {.path .Rprofile}")
  } else {
    cli::cli_alert_success("Writing {.path .Rprofile}")
  }
  invisible(TRUE)
}

remove_rprofile_block = function(root) {
  file = file.path(root, ".Rprofile")
  if (!file.exists(file)) return(invisible(FALSE))
  lines = read_lines(file)
  if (!has_block(lines)) return(invisible(FALSE))

  start = which(lines == block_start)[1]
  end = which(lines == block_end & seq_along(lines) > start)[1]
  rest = lines[-(start:end)]
  while (length(rest) && !nzchar(trimws(rest[length(rest)]))) rest = rest[-length(rest)]

  if (length(rest) == 0) {
    unlink(file)
    cli::cli_alert_success("Removing {.path .Rprofile}")
  } else {
    write_lines(rest, file)
    cli::cli_alert_success("Removing the timeknit block from {.path .Rprofile}")
  }
  invisible(TRUE)
}

profile_lines = function(previous_profile = NA_character_) {
  c(
    managed_note,
    "# Quarto starts R in each document's directory with R_PROFILE_USER pointing here",
    "# (see _environment.local), so R reads only this file. Load the profile R would",
    "# otherwise have used, then activate timeknit.",
    "local({",
    if (is.na(previous_profile)) {
      '  profile = if (file.exists(".Rprofile")) ".Rprofile" else "~/.Rprofile"'
    } else {
      paste0("  profile = ", encodeString(previous_profile, quote = '"'))
    },
    "  if (file.exists(profile)) source(profile)",
    "})",
    activation_line
  )
}

write_profile = function(root, previous_profile = NA_character_) {
  file = file.path(root, profile_name)
  wanted = profile_lines(previous_profile)
  if (file.exists(file) && identical(read_lines(file), wanted)) {
    cli::cli_alert_success("{.path {profile_name}} is up to date")
    return(invisible(FALSE))
  }
  write_lines(wanted, file)
  cli::cli_alert_success("Writing {.path {profile_name}}")
  invisible(TRUE)
}

remove_profile = function(root) {
  file = file.path(root, profile_name)
  if (!file.exists(file)) return(invisible(FALSE))
  unlink(file)
  cli::cli_alert_success("Removing {.path {profile_name}}")
  invisible(TRUE)
}

profile_user_line = function(root) {
  target = file.path(root, profile_name)
  if (grepl("'", target, fixed = TRUE)) {
    cli::cli_abort("The project path contains a single quote, which {.path {env_local_name}} cannot hold")
  }
  paste0("R_PROFILE_USER='", target, "'")
}

update_environment_local = function(root) {
  file = file.path(root, env_local_name)
  wanted = profile_user_line(root)
  lines = if (file.exists(file)) read_lines(file) else character()
  i = grep("^\\s*(export\\s+)?R_PROFILE_USER\\s*=", lines)

  if (length(i) == 1L && identical(trimws(lines[i]), wanted)) {
    cli::cli_alert_success("{.path {env_local_name}} already points {.envvar R_PROFILE_USER} at {.path {profile_name}}")
    return(invisible(FALSE))
  }
  if (length(i)) {
    old = dotenv_value(lines, "R_PROFILE_USER")
    saved = i[trimws(lines[i]) != wanted]
    lines[saved] = paste0(saved_profile_prefix, lines[saved])
    lines = lines[trimws(lines) != wanted]
    cli::cli_alert_info("Preserving {.envvar R_PROFILE_USER} ({.path {old}}) in {.path {env_local_name}}")
  } else {
    cli::cli_alert_success("Setting {.envvar R_PROFILE_USER} in {.path {env_local_name}}")
  }
  lines = c(lines, wanted)
  write_lines(lines, file)
  invisible(TRUE)
}

remove_environment_local = function(root) {
  file = file.path(root, env_local_name)
  if (!file.exists(file)) return(invisible(FALSE))
  lines = read_lines(file)
  i = which(trimws(lines) == profile_user_line(root))
  saved = startsWith(lines, saved_profile_prefix)
  if (length(i) == 0 && !any(saved)) return(invisible(FALSE))

  rest = if (length(i)) lines[-i] else lines
  saved = startsWith(rest, saved_profile_prefix)
  rest[saved] = substring(rest[saved], nchar(saved_profile_prefix) + 1L)
  if (all(!nzchar(trimws(rest)))) {
    unlink(file)
    cli::cli_alert_success("Removing {.path {env_local_name}}")
  } else {
    write_lines(rest, file)
    cli::cli_alert_success("Removing {.envvar R_PROFILE_USER} from {.path {env_local_name}}")
  }
  invisible(TRUE)
}

original_profile_user = function(root) {
  for (name in c(env_local_name, "_environment")) {
    file = file.path(root, name)
    if (!file.exists(file)) next
    lines = read_lines(file)
    # Ignore our active assignment, then recover the original assignments in order.
    lines = lines[trimws(lines) != profile_user_line(root)]
    saved = startsWith(lines, saved_profile_prefix)
    lines[saved] = substring(lines[saved], nchar(saved_profile_prefix) + 1L)
    value = dotenv_value(lines, "R_PROFILE_USER")
    if (!is.na(value)) return(value)
  }
  NA_character_
}

update_gitignore = function(root) {
  if (!in_git_repo(root)) return(invisible(FALSE))
  file = file.path(root, ".gitignore")
  lines = if (file.exists(file)) read_lines(file) else character()
  if (any(trimws(lines) %in% c(env_local_name, paste0("/", env_local_name)))) return(invisible(FALSE))
  write_lines(c(lines, env_local_name), file)
  cli::cli_alert_success("Adding {.path {env_local_name}} to {.path .gitignore}")
  invisible(TRUE)
}

dotenv_value = function(lines, key) {
  lines = sub("^\\s*export\\s+", "", lines)
  pattern = paste0("^\\s*", key, "\\s*=\\s*(.*)$")
  hits = grep(pattern, lines, value = TRUE)
  if (length(hits) == 0) return(NA_character_)
  value = trimws(sub(pattern, "\\1", hits[length(hits)]))
  if (grepl("^'.*'$", value)) return(substr(value, 2, nchar(value) - 1))
  if (grepl('^".*"$', value)) {
    value = substr(value, 2, nchar(value) - 1)
  } else {
    value = trimws(sub("\\s+#.*$", "", value))
  }
  expand_env(value)
}

expand_env = function(x) {
  refs = unique(regmatches(x, gregexpr("\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}", x))[[1]])
  for (ref in refs) {
    x = gsub(ref, Sys.getenv(substr(ref, 3, nchar(ref) - 1)), x, fixed = TRUE)
  }
  x
}

dotenv_profile_user = function(root) {
  for (name in c(env_local_name, "_environment")) {
    file = file.path(root, name)
    if (!file.exists(file)) next
    value = dotenv_value(read_lines(file), "R_PROFILE_USER")
    if (!is.na(value)) return(list(file = name, value = value))
  }
  NULL
}

find_documents = function(root, subdirs_only = FALSE) {
  files = list.files(root, pattern = "\\.(qmd|Rmd|rmd|rmarkdown)$", recursive = TRUE)
  dirs = strsplit(dirname(files), "/", fixed = TRUE)
  skip = vapply(dirs, function(d) {
    d = d[d != "."]
    any(grepl("^[._]", d) | d %in% c("renv", "node_modules"))
  }, logical(1))
  files = files[!skip]
  if (subdirs_only) files[dirname(files) != "."] else files
}
