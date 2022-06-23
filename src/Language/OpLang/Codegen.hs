module Language.OpLang.Codegen(compile) where

import Control.Monad(unless)
import Control.Monad.IO.Class(liftIO)
import Control.Monad.Reader(ask)
import Data.Char(ord)
import Data.Map.Strict qualified as M
import Data.Text(Text)
import Data.Text.IO qualified as T
import System.Directory(removeFile)
import System.FilePath(dropExtension)
import System.Process(system)
import Data.Text.Builder.Linear(Builder, fromDec, runBuilder)

import Opts
import Comp
import Language.OpLang.IR

type CCode = Builder

cName :: Id -> CCode
cName n = "o" <> fromDec (ord n)

programPrologue :: Word -> Word -> CCode
programPrologue stackSize tapeSize =
  "#include<stdio.h>\n#define T " <> fromDec tapeSize
  <> "\nchar q[" <> fromDec stackSize <> "],*s=q;"

compileProto :: Id -> CCode
compileProto name = "void " <> cName name <> "();"

compileDef :: Id -> [Instr] -> CCode
compileDef name body = "void " <> cName name <> "(){char u[T]={0},*t=u;" <> compileOps body <> "}"

compileMain :: [Instr] -> CCode
compileMain body = "int main(){char u[T]={0},*t=u;" <> compileOps body <> "return 0;}"

compileOps :: [Instr] -> CCode
compileOps = foldMap compileOp

tape :: Offset -> CCode
tape 0 = "*t"
tape off = "t[" <> fromDec off <> "]"

compileOp :: Instr -> CCode
compileOp = \case
    Add n o
      | n > 0 -> tape o <> "+=" <> fromDec n <> ";"
      | otherwise -> tape o <> "-=" <> fromDec (-n) <> ";"
    Set n o -> tape o <> "=" <> fromDec n <> ";"
    Pop o -> tape o <> "=*(--s);"
    Push o -> "*(s++)=" <> tape o <> ";"
    Read o -> "scanf(\"%c\",&" <> tape o <> ");"
    Write o -> "printf(\"%c\"," <> tape o <> ");"
    Move n
      | n > 0 -> "t+=" <> fromDec n <> ";"
      | otherwise -> "t-=" <> fromDec (-n) <> ";"
    AddCell 1 o -> tape o <> "+=*t;*t=0;"
    AddCell -1 o -> tape o <> "-=*t;*t=0;"
    AddCell n o
      | n > 0 -> tape o <> "+=*t*" <> fromDec n <> ";*t=0;"
      | otherwise -> tape o <> "-=*t*" <> fromDec (-n) <> ";*t=0;"
    Loop ops -> "while(*t){" <> compileOps ops <> "}"
    Call c -> cName c <> "();"

codegen :: Word -> Word -> Program Instr -> Text
codegen stackSize tapeSize Program{..} =
  runBuilder
  $ programPrologue stackSize tapeSize
  <> foldMap compileProto (M.keys opDefs)
  <> M.foldMapWithKey compileDef opDefs
  <> compileMain topLevel

cFile :: FilePath -> FilePath
cFile file = dropExtension file <> ".c"

compile :: Program Instr -> Comp ()
compile p = do
  Opts{..} <- ask
  let cPath = cFile optsPath
  let code = codegen optsStackSize optsTapeSize p

  liftIO do
    T.writeFile cPath code
    system $ show optsCCPath <> " -o " <> show optsOutPath <> " " <> show cPath

    unless optsKeepCFile $
      removeFile cPath
