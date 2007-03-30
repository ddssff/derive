{-# OPTIONS_GHC -fglasgow-exts -fno-monomorphism-restriction #-}

-- | The core module of the Data.Derive system.  This module contains
-- the data types used for communication between the extractors and
-- the derivors.
module Data.Derive where

import Data.List
import Data.Maybe
import Data.Char

import Language.Haskell.TH.Syntax

-- * The main data types used by Derive

-- | The type of (algebraic) data declarations.
data DataDef = DataDef {
      dataName :: String,    -- ^ The name of the data type
      dataFree :: Int,       -- ^ The number of arguments to the type
                             -- constructor (eg 3 for @data Foo b c d = ...@)
      dataCtors :: [CtorDef] -- ^ The constructors of the type
    } deriving (Eq, Ord)

-- | The type of individual data constructors.
data CtorDef = CtorDef {
      ctorName :: String,  -- ^ The constructor's name.
      ctorArity :: Int,    -- ^ Number of arguments required by this
                           -- constructor.
      ctorTypes :: [RType] -- ^ The types of the required arguments.
    } deriving (Eq, Ord)

-- | A referencing type.  An object of this type refers to some other
-- type.  Presently it is used to specify (components of) the types of
-- constructor arguments.
--
-- @Type@ values are represented in uncurried form, with a principle
-- type constructor followed by a list of zero or more arbitrary type
-- arguments.  The structure of the type guaranteed that the
-- applications are in canononical form.
data RType    = RType {typeCon :: TypeCon, typeArgs :: [RType] }
	deriving (Eq, Ord)

-- | A referencing type which is not itself an application.
data TypeCon = TypeCon String -- ^ A type defined elsewhere, free in
                              -- the data declaration.
             | TypeArg  Int   -- ^ A reference to a type bound by the
                              -- type constructor; the argument to
                              -- @TypeArg@ is the index of the type
                              -- argument, counting from zero at the
                              -- left.
	deriving (Eq, Ord)

instance Show DataDef where
    show (DataDef name arity ctors) = name ++ " #" ++ show arity ++ (if null ctors then "" else " = ") ++ c
        where c = concat $ intersperse " | " $ map show ctors

instance Show CtorDef where
    show (CtorDef name arity ts) = name ++ " #" ++ show arity ++ " : " ++ show ts

instance Show RType where
    show (RType con [])   = show con
    show (RType con args) = "(" ++ show con ++ concatMap ((" "++) . show) args ++ ")"

instance Show TypeCon where
    show (TypeCon n) = n
    show (TypeArg i) = [chr (ord 'a' + i)]

-- | The type of ways to derive classes.
data Derivation = Derivation {
      derivationDeriver :: DataDef -> [Dec], -- ^ The derivation function proper
      derivationName    :: String            -- ^ The name of the derivation
    }

-- * Template Haskell helper functions
--
-- These small short-named functions are intended to make the
-- construction of abstranct syntax trees less tedious.

-- | A simple clause, without where or guards.
sclause pats body = Clause pats (NormalB body) []

-- | A default clause with N arguments.
defclause num = sclause (replicate num WildP)

-- | The class used to overload lifting operations.  To reduce code
-- duplication, we overload the wrapped constructors (and everything
-- else, but that's irrelevant) to work both in patterns and
-- expressions.
class Valcon a where
      -- | Build an application node, with a name for a head and a
      -- provided list of arguments.
      lK :: String -> [a] -> a
      -- | Reference a named variable.
      vr :: String -> a
instance Valcon Exp where
      lK nm@(x:_) | isLower x = foldl AppE (VarE (mkName nm))
      lK nm = foldl AppE (ConE (mkName nm))
      vr = VarE . mkName
instance Valcon Pat where
      lK = ConP . mkName
      vr = VarP . mkName

-- * Lift a constructor over a fixed number of arguments.

l0 s     = lK s []
l1 s a   = lK s [a]
l2 s a b = lK s [a,b]

-- * Pre-lifted versions of common operations
true = l0 "True"
false = l0 "False"

(==:) = l2 "=="
(&&:) = l2 "&&"

-- | Build a chain of and-expressions.
and' [] = true
and' ls = foldr1 (&&:) ls

-- | Build an instance of a class for a data type, using the heuristic
-- that the type is itself required on all type arguments.
simple_instance cls (DataDef name arity _) defs = [InstanceD ctx hed defs]
    where
        vars = map (VarT . mkName . ('t':) . show) [1..arity]
        hed = ConT (mkName cls) `AppT` (foldl1 AppT (ConT (mkName name) : vars))
        ctx = map (ConT (mkName cls) `AppT`) vars

-- | Build a fundecl with a string name
funN nam claus = FunD (mkName nam) claus
