{-# LANGUAGE PatternGuards #-}

module Guess where

import HSE
import DSL
import Apply
import Data.List
import Data.Char
import Data.Maybe


data Guess = Guess DSL
           | GuessInt Int (DSL -> DSL)
           | GuessCtr Int Bool DSL  -- 0 based index, does it mention CtorName


instance Show Guess where
    show (Guess x) = show x
    show (GuessInt i f) = "(" ++ show i ++ " -> " ++ show (f $ String "?") ++ ")"
    show (GuessCtr i b x) = "(" ++ show i ++ " " ++ show b ++ " " ++ show x ++ ")"

ctrNames = ["CtorZero","CtorOne","CtorTwo"]


guess :: Res -> [DSL]
guess x = [y | Guess y <- gss (toUniverse x)]


gss :: Universe -> [Guess]

gss (UApp "InstDecl" [UList ctxt,name,typ,bod])
    | UApp "UnQual" [UApp "Ident" [UString name]] <- name
    , UList [UApp "TyApp"
        [UApp "TyCon" [UApp "UnQual" [UApp "Ident" [UString "Ctors"]]]
        ,UApp "TyVar" [UApp "Ident" [UString var]]]] <- typ
    , ctxt <- [x | UApp "ClassA" [UApp "UnQual" [UApp "Ident" [UString x]],_] <- ctxt]
    = [Guess $ Instance ctxt name y | Guess y <- gss bod]

gss (UList xs) = gssList xs
gss (UApp op xs) = map (lift (App op)) $ gssList xs

gss (UString x) 
    | Just i <- findIndex (==x) ctrNames = [GuessCtr i True CtorName]
    | otherwise = [Guess $ String x] ++
        [GuessInt (read [last x]) $ \d -> append (String $ init x) (ShowInt d) | x /= "", isDigit (last x)]

gss x = error $ show ("fallthrough",x)

-- gss x = [Guess $ fromUni x]



{-
First try and figure out runs to put them in to one possible option
Then try and figure out similarities to give them the same type
-}
gssList :: [Universe] -> [Guess]
gssList xs = mapMaybe sames $ map diffs $ sequence $ map gss xs
    where
        -- Given a list of guesses, try and collapse them into one coherent guess
        -- Each input Guess will guess at a List, so compose with Concat
        sames :: [Guess] -> Maybe Guess
        sames xs = do
            let (is,fs) = unzip $ map fromGuess xs
            i <- maxim is
            return $ toGuess i $ \x -> Concat $ List $ map ($x) fs

        -- Promote each Guess to be a list
        diffs :: [Guess] -> [Guess]

        diffs (GuessCtr 0 True x0:GuessCtr 1 True x1:GuessCtr 2 True x2:xs)
            | f 0 x0 == f 0 x1 && f 2 x2 == f 2 x1 = Guess (MapCtor x1) : diffs xs
            where f i x = apply2 dataTypeCtors (Just i) Nothing Nothing x
        
        diffs (GuessInt 1 x1:GuessInt 2 x2:xs)
            | f 1 x1 == f 1 x2 = GuessCtr 1 False (MapField (x2 FieldInd)) : diffs xs
            where f i x = apply2 dataTypeCtors Nothing (Just i) Nothing (x FieldInd)
        
        diffs (x:xs) = lift box x : diffs xs
        diffs [] = []


lift :: (DSL -> DSL) -> Guess -> Guess
lift f x = toGuess a (f . b)
    where (a,b) = fromGuess x


type GuessState = Maybe (Either Int (Int,Bool))

fromGuess :: Guess -> (GuessState, DSL -> DSL)
fromGuess (Guess x) = (Nothing, const x)
fromGuess (GuessInt i f) = (Just (Left i), f)
fromGuess (GuessCtr i b x) = (Just (Right (i,b)), const x)

toGuess :: GuessState -> (DSL -> DSL) -> Guess
toGuess Nothing f = Guess (f undefined)
toGuess (Just (Left i)) f = GuessInt i f
toGuess (Just (Right (i,b))) f = GuessCtr i b (f undefined)



-- return the maximum element, if one exists
maxim :: [GuessState] -> Maybe GuessState
maxim [] = Just Nothing
maxim [x] = Just x
maxim (Nothing:xs) = maxim xs
maxim (x:Nothing:xs) = maxim $ x:xs
maxim (x1:x2:xs) | x1 == x2 = maxim $ x1:xs
maxim (Just (Right (i1,b1)):Just (Right (i2,b2)):xs) | i1 == i2 = maxim $ Just (Right (i1,max b1 b2)) : xs
maxim _ = Nothing