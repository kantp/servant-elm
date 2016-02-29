{-# LANGUAGE FlexibleContexts #-}
module Servant.Elm.Generate where

import Control.Lens ((^.))
import           Data.List           (intercalate, nub)
import           Data.Maybe          (catMaybes)
import           Data.Proxy          (Proxy)
import qualified Data.Text           as T
import qualified Data.Text.Encoding           as T
import           Servant.Elm.Foreign (LangElm, GeneratedElm(..), getEndpoints)
import qualified Servant.Foreign     as F


{-|
Options to configure how code is generated.
-}
data ElmOptions = ElmOptions
  { {- | The protocol, host and any path prefix to be used as the base for all
    requests.

    Example: @"https://mydomain.com/api/v1"@
    -}
    urlPrefix :: String }


{-|
The default options for generating Elm code.

[@urlPrefix@] (An empty string)
-}
defElmOptions :: ElmOptions
defElmOptions = ElmOptions
  { urlPrefix = "" }


{-|
Default imports required by generated Elm code.

You probably want to include this at the top of your generated Elm module.

The default required imports are:

> import Json.Decode exposing ((:=))
> import Json.Decode.Extra exposing ((|:))
> import Json.Encode
> import Http
> import String
> import Task
-}
defElmImports :: String
defElmImports =
  unlines
    [ "import Json.Decode exposing ((:=))"
    , "import Json.Decode.Extra exposing ((|:))"
    , "import Json.Encode"
    , "import Http"
    , "import String"
    , "import Task"
    ]


{-|
Generate Elm code for the API with default options.

Returns a list of Elm code definitions with everything you need to query your
Servant API from Elm: type definitions, JSON decoders, JSON encoders, and query
functions.

You could spit these out to a file and call them from your Elm code, but you
would be better off creating a 'Spec' with the result and using 'specsToDir',
which handles the module name for you.
-}
generateElmForAPI
  :: ( F.HasForeign LangElm GeneratedElm api
     , F.GenerateList GeneratedElm (F.Foreign GeneratedElm api))
  => Proxy api
  -> [String]
generateElmForAPI =
  generateElmForAPIWith defElmOptions


{-|
Generate Elm code for the API with custom options.
-}
generateElmForAPIWith
  :: ( F.HasForeign LangElm GeneratedElm api
     , F.GenerateList GeneratedElm (F.Foreign GeneratedElm api))
  => ElmOptions
  -> Proxy api
  -> [String]
generateElmForAPIWith opts =
  nub . concatMap (generateElmForRequest opts) . getEndpoints


generateElmForRequest :: ElmOptions -> F.Req GeneratedElm -> [String]
generateElmForRequest opts request =
  allGeneratedSources elmTypeSources request
  ++ allGeneratedSources elmDecoderSources request
  ++ [funcDef]
  where
    funcDef =
      (intercalate "\n" . filter (not . null))
        [ fnName ++ " : " ++ typeSignature request
        , fnNameArgs ++ " ="
        , "  let"
        , mkLetQueryParams "    " request
        , "    request ="
        , "      { verb ="
        , "          \"" ++ method ++ "\""
        , "      , headers ="
        , "          [(\"Content-Type\", \"application/json\")]"
        , "      , url ="
        , "          " ++ url
        , mkQueryParams "          " request
        , "      , body ="
        , "          " ++ body
        , "      }"
        , "  in"
        , "    Http.fromJson"
        , "      " ++ decoder
        , "      (Http.send Http.defaultSettings request)"
        ]

    fnName =
      T.unpack (F.camelCase (request ^. F.funcName))

    fnNameArgs =
      unwords (fnName : args)

    args =
      [ T.unpack $ F.captureArg segment ^. F.argName
      | segment <- request ^. F.reqUrl . F.path
      , F.isCapture segment
      ]
      ++
      [ T.unpack $ arg ^. F.queryArg . F.argName
      | arg <- request ^. F.reqUrl . F.queryStr
      ]
      ++
      catMaybes
        [ fmap (const "body") (request ^. F.reqBody)
        ]

    method =
       T.unpack (T.decodeUtf8 (request ^. F.reqMethod))

    url =
      mkUrl (urlPrefix opts) (request ^. F.reqUrl . F.path)

    body =
      maybe
        "Http.empty"
        (\generatedElm ->
          "Http.string (Json.Encode.encode 0 (" ++ elmEncoder generatedElm ++ " body))")
        (request ^. F.reqBody)

    decoder =
      maybe "(succeed ())" elmDecoder (request ^. F.reqReturnType)

typeSignature
  :: F.Req GeneratedElm
  -> String
typeSignature request =
  (intercalate " -> " . catMaybes)
    [ urlTypes
    , queryTypes
    , bodyType
    , returnType
    ]
  where
    urlCaptureArgs =
      [ F.captureArg cap
      | cap <- request ^. F.reqUrl . F.path
      , F.isCapture cap
      ]
    urlTypes =
      if null urlCaptureArgs then
        Nothing
      else
        Just $ intercalate " -> "
          [ elmType (arg ^. F.argType)
          | arg <- urlCaptureArgs
          ]

    queryArgToElmType arg =
      let
        eType = elmType (arg ^. F.queryArg . F.argType)
      in
        case arg ^. F.queryArgType of
          F.Normal ->
            "Maybe (" ++ eType ++ ")"
          _ ->
            eType

    queryTypes =
      if null (request ^. F.reqUrl . F.queryStr) then
        Nothing
      else
        Just . intercalate " -> " $
          map queryArgToElmType (request ^. F.reqUrl . F.queryStr)

    bodyType =
      fmap elmType (request ^. F.reqBody)

    returnType =
      fmap
        (\generatedElm ->
           "Task.Task Http.Error (" ++ elmType generatedElm ++ ")")
        (request ^. F.reqReturnType)

mkUrl
  :: String
  -> [F.Segment GeneratedElm]
  -> String
mkUrl prefix segments =
  (intercalate newLine . catMaybes)
    [ nullOr prefix $
        "\"" ++ prefix ++ "\""
    , nullOr segments $
        "\"/\" ++ "
        ++ intercalate (newLine ++ "\"/\" ++ ")
              (map segmentToStr segments)
    ]
  where
    newLine =
      "\n          ++ "

    nullOr t x =
      if null t then
         Nothing
      else
        Just x

    segmentToStr s =
      case s ^. F.segment of
        F.Static path ->
          "\"" ++ T.unpack path ++ "\""
        F.Cap arg ->
          "(" ++ T.unpack (arg ^. F.argName) ++ " |> toString |> Http.uriEncode)"

mkLetQueryParams
  :: String
  -> F.Req GeneratedElm
  -> String
mkLetQueryParams indent request =
  if null (request ^. F.reqUrl . F.queryStr) then
    ""
  else
    indent
    ++ intercalate ("\n" ++ indent)
        [ "params ="
        , "  List.filter (not << String.isEmpty)"
        , "    [ " ++ intercalate ("\n" ++ indent ++ "    , ") params
        , "    ]"
        ]
  where
    params = map paramToStr (request ^. F.reqUrl . F.queryStr)

    paramToStr qarg =
      case qarg ^. F.queryArgType of
        F.Normal ->
          intercalate newLine
            [ name
            , "  |> Maybe.map (toString >> Http.uriEncode >> (++) \"" ++ name ++ "=\")"
            , "  |> Maybe.withDefault \"\""
            ]
        F.Flag ->
          intercalate newLine
            ["if " ++ name ++ " then"
            , "  \"" ++ name ++ "=\""
            , "else"
            , "  \"\""
            ]
        F.List ->
          intercalate newLine
            [ name
            , "  |> List.map (\\val -> \"" ++ name ++ "[]=\" ++ (val |> toString |> Http.uriEncode))"
            , "  |> String.join \"&\""
            ]
      where name = T.unpack (qarg ^. F.queryArg . F.argName)
            newLine = "\n          "

mkQueryParams
  :: String
  -> F.Req GeneratedElm
  -> String
mkQueryParams indent request =
  if null (request ^. F.reqUrl . F.queryStr) then
    ""
  else
    indent
    ++ intercalate ("\n" ++ indent)
        [ "++ if List.isEmpty params then"
        , "     \"\""
        , "   else"
        , "     \"?\" ++ String.join \"&\" params"
        ]


allGeneratedSources
  :: (GeneratedElm -> [String])
  -> F.Req GeneratedElm
  -> [String]
allGeneratedSources f request =
  fromUrl ++ fromBody ++ fromReturnType
  where
    fromUrl =
      []
    fromBody =
      maybe [] f (request ^. F.reqBody)
    fromReturnType =
      maybe [] f (request ^. F.reqReturnType)
