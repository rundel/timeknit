#' Report timeknit's status for a project
#'
#' Prints a situation report: whether timeknit is active in this session and
#' knitr's progress display is enabled, which profiles activate it for the
#' project, and which documents in the project are reached when rendered with
#' Quarto. Nothing is changed.
#'
#' A document is counted as covered when the profile R will read for it
#' activates timeknit. Quarto starts R in the document's directory, so that
#' profile is `R_PROFILE_USER` if set (in this session's environment or in the
#' project's `_environment.local` or `_environment`), otherwise a `.Rprofile` in
#' the document's directory, otherwise `~/.Rprofile`.
#'
#' @inheritParams use_timeknit_project
#' @return A list with the collected facts, invisibly. The `documents` element
#'   is a data frame with one row per directory holding `.qmd` or `.Rmd` files.
#' @seealso [use_timeknit_project()] to set a project up.
#' @export
sitrep = function(path = ".") {
  root = find_root(path)
  user = profile_status(user_profile_path())
  env = env_profile_user()
  dotenv = if (is_quarto_project(root)) dotenv_profile_user(root)
  effective_env = if (!is.na(env)) env else if (!is.null(dotenv)) dotenv$value else NA_character_

  info = list(
    timeknit_version = utils::packageVersion("timeknit"),
    timeknit_lib = dirname(system.file(package = "timeknit")),
    dev_dir = dev_dir(),
    installed_libs = installed_libs(),
    knitr_progress = isTRUE(knitr::opts_knit$get("progress")),
    session = session_status(),
    record = getOption("timeknit.record", TRUE),
    user_profile = user,
    env_profile = env,
    env_profile_status = if (!is.na(env)) profile_status(path.expand(env), user),
    root = root,
    marker = root_marker(root),
    kinds = project_kinds(root),
    quarto = is_quarto_project(root),
    git = in_git_repo(root),
    rprofile = profile_status(file.path(root, ".Rprofile"), user),
    environment = environment_status(root, dotenv, user),
    documents = document_status(root, effective_env, user)
  )
  print_sitrep(info)
  invisible(info)
}

session_status = function() {
  fun = getOption("knitr.progress.fun")
  if (is.null(fun)) return("unset")
  if (is_timeknit_progress(fun)) "timeknit" else "other"
}

is_timeknit_progress = function(fun) {
  if (!is.function(fun)) return(FALSE)
  env = environment(fun)
  if (!is.null(env) && isNamespace(env) && identical(unname(getNamespaceName(env)), "timeknit")) return(TRUE)
  any(grepl("knit_progress", deparse(body(fun)), fixed = TRUE))
}

dev_dir = function() {
  dir = system.file(package = "timeknit")
  if (file.exists(file.path(dir, "Meta"))) NULL else dir
}

installed_libs = function() {
  libs = .libPaths()
  libs[file.exists(file.path(libs, "timeknit", "Meta", "package.rds"))]
}
profile_status = function(file, user = NULL) {
  exists = file.exists(file)
  lines = if (exists) read_lines(file) else character()
  direct = activates_timeknit(lines)
  sources_user = sources_user_profile(lines)
  list(
    path = file,
    exists = exists,
    direct = direct,
    sources_user = sources_user,
    activates = direct || (sources_user && isTRUE(user$activates)),
    managed = has_block(lines)
  )
}

environment_status = function(root, dotenv, user) {
  if (is.null(dotenv)) return(NULL)
  target = path.expand(dotenv$value)
  if (!is_absolute(target)) target = file.path(root, target)
  c(dotenv, list(target = target), profile_status(target, user)[c("exists", "activates")])
}

is_absolute = function(path) {
  grepl("^(/|~|[A-Za-z]:[/\\\\])", path)
}

document_status = function(root, effective_env, user) {
  docs = find_documents(root)
  dirs = unique(dirname(docs))
  rows = lapply(dirs, function(dir) {
    abs = normalizePath(file.path(root, dir))
    profile = if (!is.na(effective_env)) {
      expanded = path.expand(effective_env)
      if (is_absolute(expanded)) expanded else file.path(abs, expanded)
    } else if (file.exists(file.path(abs, ".Rprofile"))) {
      file.path(abs, ".Rprofile")
    } else {
      user_profile_path()
    }
    status = profile_status(profile, user)
    data.frame(
      dir = dir, n = sum(dirname(docs) == dir), profile = profile,
      exists = status$exists, covered = status$activates, stringsAsFactors = FALSE
    )
  })
  if (length(rows) == 0) {
    return(data.frame(
      dir = character(), n = integer(), profile = character(),
      exists = logical(), covered = logical(), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

pretty_path = function(path, root) {
  home = path.expand("~")
  if (startsWith(path, paste0(root, "/"))) return(substring(path, nchar(root) + 2))
  if (startsWith(path, paste0(home, "/"))) return(paste0("~", substring(path, nchar(home) + 1)))
  path
}

print_sitrep = function(x) {
  cli::cli_rule("timeknit sitrep")
  if (!is.null(x$dev_dir) && length(x$installed_libs) == 0) {
    cli::cli_alert_danger("timeknit is loaded from source at {.path {x$dev_dir}} but not installed in any library on {.code .libPaths()}, so profiles in other R sessions cannot load it")
  }
  if (!x$knitr_progress) {
    cli::cli_alert_warning("This session: knitr's progress display is disabled through {.code knitr::opts_knit}, so nothing will be printed")
  }

  if (x$session == "timeknit") {
    cli::cli_alert_success("This session: {.code knitr.progress.fun} points to timeknit")
  } else if (x$session == "other") {
    cli::cli_alert_warning("This session: {.code knitr.progress.fun} is set to something other than timeknit")
  } else {
    cli::cli_alert_danger("This session: {.code knitr.progress.fun} is not set; call {.run timeknit::use_timeknit()} or restart R")
  }
  if (isFALSE(x$record)) {
    cli::cli_alert_info("This session: timing records are disabled ({.code timeknit.record} is {.code FALSE}), so editor integrations have nothing to read")
  }

  kinds = if (length(x$kinds)) paste(x$kinds, collapse = ", ") else "no _quarto.yml, .Rproj, DESCRIPTION, or .git found, using the directory as given"
  cli::cli_alert_info("Project: {.path {x$root}} ({kinds})")

  if (!is.na(x$env_profile)) {
    env = x$env_profile_status
    if (!env$exists) {
      cli::cli_alert_danger("{.envvar R_PROFILE_USER} is {.path {x$env_profile}} in this session, which does not exist, so R reads no profile at all")
    } else if (env$activates) {
      cli::cli_alert_success("{.envvar R_PROFILE_USER} is {.path {x$env_profile}} in this session, which activates timeknit")
    } else {
      cli::cli_alert_warning("{.envvar R_PROFILE_USER} is {.path {x$env_profile}} in this session, which does not activate timeknit; Quarto keeps it over {.path _environment.local}")
    }
  }

  env = x$environment
  if (!is.null(env)) {
    if (!env$exists) {
      cli::cli_alert_danger("{.path {env$file}} points {.envvar R_PROFILE_USER} at {.path {env$value}}, which does not exist, so R reads no profile at all")
    } else if (env$activates) {
      cli::cli_alert_success("{.path {env$file}} points {.envvar R_PROFILE_USER} at {.path {pretty_path(env$target, x$root)}}, which activates timeknit")
    } else {
      cli::cli_alert_danger("{.path {env$file}} points {.envvar R_PROFILE_USER} at {.path {pretty_path(env$target, x$root)}}, which does not activate timeknit")
    }
  }

  rp = x$rprofile
  user = x$user_profile
  if (rp$activates) {
    how = c(if (rp$managed) "managed block", if (rp$sources_user) "sources ~/.Rprofile")
    cli::cli_alert_success("{.path .Rprofile} activates timeknit{if (length(how)) paste0(' (', paste(how, collapse = ', '), ')')}")
  }
  if (rp$exists && !rp$sources_user && user$exists) {
    cli::cli_alert_info("{.path .Rprofile} replaces {.path ~/.Rprofile} for sessions started here and does not source it")
  }
  if (user$activates) {
    cli::cli_alert_success("{.path ~/.Rprofile} activates timeknit")
  }

  docs = x$documents
  total = sum(docs$n)
  if (total == 0) {
    cli::cli_alert_info("No {.file .qmd} or {.file .Rmd} documents found")
  } else if (all(docs$covered)) {
    cli::cli_alert_success("Quarto renders: all {total} document{?s} in {nrow(docs)} director{?y/ies} are covered")
  } else {
    missing = docs[!docs$covered, ]
    n_missing = sum(missing$n)
    cli::cli_alert_danger("Quarto renders: {n_missing} of {total} document{?s} are not covered")
    cli::cli_ul()
    for (i in seq_len(nrow(missing))) {
      n = missing$n[i]
      label = if (missing$dir[i] == ".") "project root" else missing$dir[i]
      profile = pretty_path(missing$profile[i], x$root)
      state = if (missing$exists[i]) "does not activate timeknit" else "does not exist"
      cli::cli_li("{label} ({n} document{?s}) reads {.path {profile}}, which {state}")
    }
    cli::cli_end()
    if (x$quarto || all(missing$dir == ".")) {
      cli::cli_alert_info("Run {.run timeknit::use_timeknit_project()} to set this project up")
    } else {
      cli::cli_alert_info("Documents in subdirectories need a {.path _quarto.yml} so that {.path _environment.local} can point R at a profile; then run {.run timeknit::use_timeknit_project()}")
    }
  }
  invisible(x)
}

project_kinds = function(root) {
  c(
    if (is_quarto_project(root)) "Quarto project",
    if (file.exists(file.path(root, "DESCRIPTION"))) "R package",
    if (length(list.files(root, pattern = "\\.Rproj$"))) "RStudio project",
    if (in_git_repo(root)) "git repository"
  )
}
