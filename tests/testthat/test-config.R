test_that("perplexica_set_url() stores a URL and perplexica_get_url() retrieves it", {
  withr::local_options(list(perplexica.base_url = NULL))
  perplexica_set_url("http://test-host:9999")
  expect_equal(perplexica_get_url(), "http://test-host:9999")
})

test_that("perplexica_set_url() returns the URL invisibly", {
  withr::local_options(list(perplexica.base_url = NULL))
  out <- withVisible(perplexica_set_url("http://test-host:9999"))
  expect_false(out$visible)
  expect_equal(out$value, "http://test-host:9999")
})

test_that("perplexica_get_url() returns default 'http://localhost:3000' when unset", {
  withr::local_options(list(perplexica.base_url = NULL))
  expect_equal(perplexica_get_url(), "http://localhost:3000")
})

test_that("perplexica_set_url() overwrites a previously set URL", {
  withr::local_options(list(perplexica.base_url = "http://old:1111"))
  perplexica_set_url("http://new:2222")
  expect_equal(perplexica_get_url(), "http://new:2222")
})

test_that("%||% returns left-hand side when non-NULL", {
  expect_equal(perplexica:::`%||%`("a", "b"), "a")
  expect_equal(perplexica:::`%||%`(0L,   99L), 0L)
  expect_equal(perplexica:::`%||%`(FALSE, TRUE), FALSE)
})

test_that("%||% returns right-hand side when left is NULL", {
  expect_equal(perplexica:::`%||%`(NULL, "b"), "b")
  expect_equal(perplexica:::`%||%`(NULL, 42L), 42L)
})
