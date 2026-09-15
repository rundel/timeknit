local_fake_home = function(env = parent.frame()) {
  home = tempfile("home")
  dir.create(home)
  testthat::local_mocked_bindings(
    user_profile_path = function() file.path(home, ".Rprofile"),
    env_profile_user = function() NA_character_,
    .env = env
  )
  home
}

make_project = function(quarto = TRUE, git = TRUE,
                        docs = c("index.qmd", "lectures/lec01.qmd", "lectures/lec02.qmd")) {
  root = tempfile("proj")
  dir.create(root)
  root = normalizePath(root)
  if (quarto) writeLines(c("project:", "  type: default"), file.path(root, "_quarto.yml"))
  if (git) dir.create(file.path(root, ".git"))
  for (doc in docs) {
    dir.create(dirname(file.path(root, doc)), recursive = TRUE, showWarnings = FALSE)
    writeLines("# doc", file.path(root, doc))
  }
  root
}

test_that("find_root walks up to a project marker", {
  root = make_project()
  expect_equal(find_root(file.path(root, "lectures")), root)
  plain = tempfile("plain")
  dir.create(plain)
  expect_equal(find_root(plain), normalizePath(plain))
  expect_error(find_root(file.path(plain, "nope")), "not a directory")
})

test_that("use_timeknit_project sets up a quarto project and sitrep reports it", {
  local_fake_home()
  root = make_project()

  before = suppressMessages(sitrep(root))
  expect_true(before$quarto)
  expect_true(before$git)
  expect_false(before$rprofile$exists)
  expect_null(before$environment)
  expect_equal(before$documents$dir, c(".", "lectures"))
  expect_equal(before$documents$n, c(1L, 2L))
  expect_false(any(before$documents$covered))

  suppressMessages(use_timeknit_project(file.path(root, "lectures")))
  rprofile = readLines(file.path(root, ".Rprofile"))
  expect_true(any(grepl("timeknit::use_timeknit()", rprofile, fixed = TRUE)))
  expect_true(any(grepl('source("~/.Rprofile")', rprofile, fixed = TRUE)))
  expect_true(file.exists(file.path(root, ".timeknit.Rprofile")))
  env = readLines(file.path(root, "_environment.local"))
  expect_equal(env, paste0("R_PROFILE_USER='", file.path(root, ".timeknit.Rprofile"), "'"))
  expect_equal(readLines(file.path(root, ".gitignore")), "_environment.local")

  after = suppressMessages(sitrep(root))
  expect_true(after$rprofile$activates)
  expect_true(after$rprofile$managed)
  expect_true(after$rprofile$sources_user)
  expect_equal(after$environment$file, "_environment.local")
  expect_true(after$environment$activates)
  expect_true(all(after$documents$covered))

  suppressMessages(use_timeknit_project(root))
  expect_equal(readLines(file.path(root, ".Rprofile")), rprofile)
  expect_equal(readLines(file.path(root, "_environment.local")), env)
  expect_equal(readLines(file.path(root, ".gitignore")), "_environment.local")

  suppressMessages(remove_timeknit_project(root))
  expect_false(file.exists(file.path(root, ".Rprofile")))
  expect_false(file.exists(file.path(root, ".timeknit.Rprofile")))
  expect_false(file.exists(file.path(root, "_environment.local")))
  expect_true(file.exists(file.path(root, ".gitignore")))
  gone = suppressMessages(sitrep(root))
  expect_false(any(gone$documents$covered))
})

test_that("existing files keep their own content", {
  local_fake_home()
  root = make_project(git = FALSE)
  writeLines(c('options(pkgType = "source")', ""), file.path(root, ".Rprofile"))
  writeLines(c("FOO=bar", "R_PROFILE_USER=/old/profile.R"), file.path(root, "_environment.local"))

  suppressMessages(use_timeknit_project(root))
  rprofile = readLines(file.path(root, ".Rprofile"))
  expect_equal(rprofile[1], 'options(pkgType = "source")')
  expect_false(any(grepl("~/.Rprofile", rprofile, fixed = TRUE)))
  env = readLines(file.path(root, "_environment.local"))
  expect_equal(env[1], "FOO=bar")
  expect_match(env[2], "^# timeknit saved R_PROFILE_USER: R_PROFILE_USER=/old/profile.R$")
  expect_match(env[3], "^R_PROFILE_USER='.*\\.timeknit\\.Rprofile'$")
  expect_length(env, 3)
  expect_false(file.exists(file.path(root, ".gitignore")))

  status = suppressMessages(sitrep(root))
  expect_false(status$rprofile$sources_user)
  expect_true(all(status$documents$covered))

  suppressMessages(remove_timeknit_project(root))
  expect_equal(readLines(file.path(root, ".Rprofile")), 'options(pkgType = "source")')
  expect_equal(readLines(file.path(root, "_environment.local")),
               c("FOO=bar", "R_PROFILE_USER=/old/profile.R"))
})

test_that("setup preserves and restores duplicate profile assignments", {
  local_fake_home()
  root = make_project(git = FALSE)
  file = file.path(root, "_environment.local")
  original = c("FOO=bar", "R_PROFILE_USER=/first", "# keep this comment",
               "export R_PROFILE_USER = '/last'", "OTHER=value")
  writeLines(original, file)
  suppressMessages(use_timeknit_project(root))
  configured = readLines(file)
  expect_equal(dotenv_profile_user(root)$value, file.path(root, profile_name))
  expect_length(grep("^\\s*(export\\s+)?R_PROFILE_USER\\s*=", configured), 1)
  suppressMessages(use_timeknit_project(root))
  expect_equal(readLines(file), configured)
  expect_true(all(suppressMessages(sitrep(root))$documents$covered))
  suppressMessages(remove_timeknit_project(root))
  expect_equal(readLines(file), original)
})

test_that("setup repairs a later assignment after an existing managed assignment", {
  root = make_project(git = FALSE)
  file = file.path(root, "_environment.local")
  suppressMessages(use_timeknit_project(root))
  writeLines(c(readLines(file), "R_PROFILE_USER=/later"), file)
  suppressMessages(use_timeknit_project(root))
  expect_equal(dotenv_profile_user(root)$value, file.path(root, profile_name))
  expect_equal(original_profile_user(root), "/later")
  suppressMessages(remove_timeknit_project(root))
  expect_equal(readLines(file), "R_PROFILE_USER=/later")
})

test_that("custom profiles are loaded before activation and survive repeated setup", {
  local_fake_home()
  op = options(knitr.progress.fun = NULL, tk.custom = NULL)
  on.exit(options(op))
  for (env_file in c("_environment.local", "_environment")) {
    root = make_project(git = FALSE)
    custom = file.path(root, 'custom "profile".R')
    writeLines(c('options(tk.custom = "loaded")',
                 'options(knitr.progress.fun = NULL)'), custom)
    original = paste0("R_PROFILE_USER='", custom, "'")
    writeLines(original, file.path(root, env_file))
    suppressMessages(use_timeknit_project(root))
    profile = readLines(file.path(root, profile_name))
    suppressMessages(use_timeknit_project(root))
    expect_equal(readLines(file.path(root, profile_name)), profile)
    options(tk.custom = NULL, knitr.progress.fun = NULL)
    sys.source(file.path(root, profile_name), envir = new.env())
    expect_equal(getOption("tk.custom"), "loaded")
    expect_true(is_timeknit_progress(getOption("knitr.progress.fun")))
    suppressMessages(remove_timeknit_project(root))
    expect_equal(readLines(file.path(root, env_file)), original)
  }
})

test_that("unrelated progress settings do not count as timeknit activation", {
  local_fake_home()
  inactive = c(
    'options(knitr.progress.fun = NULL)',
    'options(knitr.progress.fun = function(total, labels) NULL)',
    'options(knitr.progress.fun = other::knit_progress)',
    'other::use_timeknit()',
    'message("timeknit::use_timeknit()")',
    'f = function() timeknit::use_timeknit()',
    '# timeknit::use_timeknit()'
  )
  for (line in inactive) expect_false(activates_timeknit(line), info = line)
  active = c(
    'timeknit::use_timeknit ()',
    'use_timeknit()',
    'options(knitr.progress.fun = timeknit::knit_progress)',
    'options(knitr.progress.fun = knit_progress)',
    'options(knitr.progress.fun = function(...) timeknit::knit_progress(...))'
  )
  for (line in active) expect_true(activates_timeknit(line), info = line)
  root = make_project(quarto = FALSE, git = FALSE, docs = "index.qmd")
  writeLines(inactive[1], file.path(root, ".Rprofile"))
  expect_false(any(suppressMessages(sitrep(root))$documents$covered))
  suppressMessages(use_timeknit_project(root))
  expect_true(has_block(readLines(file.path(root, ".Rprofile"))))
  expect_true(all(suppressMessages(sitrep(root))$documents$covered))
})

test_that("a directory without _quarto.yml only gets an .Rprofile", {
  local_fake_home()
  root = make_project(quarto = FALSE, git = FALSE, docs = c("a.Rmd", "sub/b.qmd"))
  messages = testthat::capture_messages(use_timeknit_project(root))
  expect_true(any(grepl("subdirectories", messages)))
  expect_true(file.exists(file.path(root, ".Rprofile")))
  expect_false(file.exists(file.path(root, ".timeknit.Rprofile")))
  expect_false(file.exists(file.path(root, "_environment.local")))

  status = suppressMessages(sitrep(root))
  expect_false(status$quarto)
  expect_equal(status$documents$covered, c(TRUE, FALSE))
})

test_that("sitrep recognises activation through ~/.Rprofile and R_PROFILE_USER", {
  home = local_fake_home()
  root = make_project(git = FALSE)
  writeLines("timeknit::use_timeknit()", file.path(home, ".Rprofile"))
  status = suppressMessages(sitrep(root))
  expect_true(status$user_profile$activates)
  expect_true(all(status$documents$covered))

  writeLines('source("~/.Rprofile")', file.path(root, ".Rprofile"))
  status = suppressMessages(sitrep(root))
  expect_true(status$rprofile$activates)
  expect_false(status$rprofile$direct)

  testthat::local_mocked_bindings(env_profile_user = function() "/nonexistent/profile.R")
  status = suppressMessages(sitrep(root))
  expect_false(status$env_profile_status$exists)
  expect_false(any(status$documents$covered))
})

test_that("dotenv values are parsed like quarto does", {
  expect_equal(dotenv_value("R_PROFILE_USER=/a/b.R", "R_PROFILE_USER"), "/a/b.R")
  expect_equal(dotenv_value("R_PROFILE_USER='/a b/c.R'", "R_PROFILE_USER"), "/a b/c.R")
  expect_equal(dotenv_value('R_PROFILE_USER="/a/b.R"', "R_PROFILE_USER"), "/a/b.R")
  expect_equal(dotenv_value("export R_PROFILE_USER=/a/b.R # note", "R_PROFILE_USER"), "/a/b.R")
  expect_equal(dotenv_value(c("R_PROFILE_USER=/first", "R_PROFILE_USER=/last"), "R_PROFILE_USER"), "/last")
  expect_equal(dotenv_value("OTHER=x", "R_PROFILE_USER"), NA_character_)
  Sys.setenv(TIMEKNIT_TEST_DIR = "/base")
  on.exit(Sys.unsetenv("TIMEKNIT_TEST_DIR"))
  expect_equal(dotenv_value("R_PROFILE_USER=${TIMEKNIT_TEST_DIR}/p.R", "R_PROFILE_USER"), "/base/p.R")
})

test_that("the generated profile loads the right profile from any directory", {
  skip_on_cran()
  rscript = file.path(R.home("bin"), "Rscript")
  skip_if_not(file.exists(rscript))

  home = tempfile("home")
  dir.create(home)
  writeLines('options(tk.test = "home")', file.path(home, ".Rprofile"))
  root = make_project(git = FALSE)
  writeLines('options(tk.test = "root")', file.path(root, ".Rprofile"))
  suppressMessages(use_timeknit_project(root))

  script = tempfile(fileext = ".R")
  writeLines('cat(getOption("tk.test"), is.function(getOption("knitr.progress.fun")))', script)
  run_in = function(dir) {
    old = setwd(dir)
    on.exit(setwd(old))
    system2(rscript, shQuote(script), stdout = TRUE, stderr = TRUE, env = c(
      paste0("HOME=", shQuote(home)),
      paste0("R_PROFILE_USER=", shQuote(file.path(root, ".timeknit.Rprofile"))),
      paste0("R_LIBS=", shQuote(paste(.libPaths(), collapse = ":")))
    ))
  }
  expect_equal(run_in(root), "root TRUE")
  expect_equal(run_in(file.path(root, "lectures")), "home TRUE")

  custom = file.path(root, "custom.Rprofile")
  writeLines('options(tk.test = "custom")', custom)
  original = paste0("R_PROFILE_USER='", custom, "'")
  writeLines(original, file.path(root, "_environment.local"))
  suppressMessages(use_timeknit_project(root))
  suppressMessages(use_timeknit_project(root))
  expect_equal(run_in(root), "custom TRUE")
  expect_equal(run_in(file.path(root, "lectures")), "custom TRUE")
  suppressMessages(remove_timeknit_project(root))
  expect_equal(readLines(file.path(root, "_environment.local")), original)
})

test_that("the session check recognises timeknit functions from any namespace copy or wrapper", {
  op = options(knitr.progress.fun = NULL)
  on.exit(options(op))
  expect_equal(session_status(), "unset")

  options(knitr.progress.fun = knit_progress)
  expect_equal(session_status(), "timeknit")

  options(knitr.progress.fun = function(...) timeknit::knit_progress(...))
  expect_equal(session_status(), "timeknit")

  options(knitr.progress.fun = function(total, labels) NULL)
  expect_equal(session_status(), "other")
})
