{-|
Basic usage:

> import MyLib (MyServantApiType)
> import Servant.Elm
>
> spec :: Spec
> spec = Spec ["Generated", "MyApi"]
>             (defElmImports : generateElmForAPI (Proxy :: Proxy MyServantApiType))
>
> main :: IO ()
> main = specsToDir [spec] "my-elm-dir"
-}
module Servant.Elm
       ( generateElmForAPI
       , generateElmForAPIWith
       , ElmOptions(..)
       , defElmOptions
       , defElmImports
       -- * Convenience re-exports from the "Elm" module
       , Spec(Spec)
       , ToElmType
       , specsToDir
       -- * Convenience re-exports from "Data.Proxy"
       , Proxy(Proxy)
       ) where

import           Servant.Elm.Generate (ElmOptions (..), defElmImports,
                                       defElmOptions, generateElmForAPI,
                                       generateElmForAPIWith)

import Data.Proxy (Proxy(Proxy))
import Elm (Spec(Spec), ToElmType, specsToDir)
