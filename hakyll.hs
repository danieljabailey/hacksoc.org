{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Applicative (Alternative(empty))
import Data.Monoid ((<>))
import Hakyll

main :: IO ()
main = hakyllWith defaultConfiguration $ do
  -- Load templates
  match "templates/*" $ compile templateCompiler

  -- Copy static files
  match "static/**" $ do
    route $ gsubRoute "static/" (const "")
    compile copyFileCompiler

  -- Build news posts
  match "news/*" $ do
    route $ setExtension ".html"
    compile $ pandocCompiler
      >>= saveSnapshot "content"
      >>= loadAndApplyTemplate "templates/news.html"    defaultContext
      >>= loadAndApplyTemplate "templates/wrapper.html" defaultContext
      >>= relativizeUrls

  -- Build index page with paginated news list
  let everyN n = fmap (paginateEvery n) . sortRecentFirst
  let fname  n = fromFilePath $ if n == 1 then "index.html" else "news-" ++ show n ++ ".html"
  paginator <- buildPaginateWith (everyN 5) "news/*" fname

  paginateRules paginator $ \pageNum pattern -> do
    route idRoute
    compile $ do
      entries <- recentFirst =<< loadAll pattern
      let ctx = dropField "title" $
            paginateContext paginator pageNum <>
            listField "entries" (excerptField "content" <> defaultContext) (return entries) <>
            defaultContext
      makeItem ""
        >>= loadAndApplyTemplate "templates/newslist.html" ctx
        >>= loadAndApplyTemplate "templates/wrapper.html"  ctx
        >>= relativizeUrls

  -- Build pages
  match "*.html" $ do
    route idRoute
    compile $ pandocCompiler
      >>= loadAndApplyTemplate "templates/wrapper.html" defaultContext
      >>= relativizeUrls

-- | Extract the first non-blank line from a news post.
excerptField :: Snapshot -> Context String
excerptField snapshot = field "excerpt" $ \item -> do
  body <- itemBody <$> loadSnapshot (itemIdentifier item) snapshot
  case lines (trim body) of
    (excerpt:_) -> return excerpt
    [] -> fail $ "excerptField: no excerpt defined for " ++ show (itemIdentifier item)

-- | Drop a field from a context.
dropField :: String -> Context a -> Context a
dropField field (Context f) = Context $ \k a i ->
  if k == field then empty else f k a i
