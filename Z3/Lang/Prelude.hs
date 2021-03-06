{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE CPP                        #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE IncoherentInstances        #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverlappingInstances       #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeSynonymInstances       #-}
{-# LANGUAGE UndecidableInstances       #-}

-- |
-- Module    : Z3.Lang.Prelude
-- Copyright : (c) Iago Abal, 2012-2013
--             (c) David Castro, 2012-2013
-- License   : BSD3
-- Maintainer: Iago Abal <iago.abal@gmail.com>,
--             David Castro <david.castro.dcp@gmail.com>
-- Stability : experimental

-- TODO: Pretty-printing of expressions

module Z3.Lang.Prelude (

    -- * Z3 script
      Z3
    , Base.Result
    , evalZ3
    , Args(..)
    , stdArgs
    , Logic(..)
    , evalZ3With

    -- ** Commands
    , var
    , namedVar
    , fun1, fun2, fun3, fun4, fun5
    , assert
    , let_
    , check
    , showContext
    , exprToString
    , push, pop

    -- ** Models
    , Model
    , checkModel
    , checkModelWith
    , checkModelWithResult
    , showModel
    , eval, evalT

    -- * Expressions
    , Expr
    , Pattern(..)
    , IsTy
    , IsNum
    , IsInt
    , IsReal
    , Castable
    , literal
    , true
    , false
    , not_
    , and_, (&&*)
    , or_, (||*)
    , distinct
    , xor
    , implies, (==>)
    , iff, (<=>)
    , forall
    , exists
    , instanceWhen
    , (//), (%*), (%%)
    , divides
    , (==*), (/=*)
    , (<=*), (<*.)
    , (>=*), (>*)
    , min_, max_
    , ite
    , cast

    ) where

-- import Z3.Base ( AST )
import qualified Z3.Base as Base
import Z3.Monad hiding ( Z3, mkEq, Pattern, Model, evalZ3, evalZ3With, eval, evalT, showModel )
import qualified Z3.Monad as MonadZ3
import Z3.Lang.Exprs
import Z3.Lang.Monad
import Z3.Lang.TY

import Control.Applicative ( Applicative, (<$>) )
import Control.Monad.Reader ( ReaderT, ask, runReaderT )
import Control.Monad.Trans ( lift )
import Data.Traversable ( Traversable )
import qualified Data.Traversable as T
#if __GLASGOW_HASKELL__ < 704
import Data.Typeable ( Typeable1(..), typeOf )
import Unsafe.Coerce ( unsafeCoerce )
#else
import Data.Typeable ( Typeable1(..) )
#endif

---------------------------------------------------------------------
-- Utils

-- | Compile while introducing TCCs into the script.
--
compileWithTCC :: IsTy a => Expr a -> Z3 Base.AST
compileWithTCC e = do
  assertCnstr =<< compile (and_ $ typecheck e)
  compile e

---------------------------------------------------------------------
-- Commands

createVar :: forall a. IsTy a => Uniq -> Symbol -> Z3 (Expr a)
createVar u sym = do
    srt  <- mkSort  (TY :: TY a)
    cnst <- mkConst sym srt
    let e = Const u cnst
    assert $ typeInv e
    return e

-- | Declare skolem variables.
var :: IsTy a => Z3 (Expr a)
var = do
    u <- fresh
    createVar u =<< mkIntSymbol u

-- | Declare skolem variables with a user specified name.
namedVar :: IsTy a => String -> Z3 (Expr a)
namedVar name = do
    u <- fresh
    createVar u =<< mkStringSymbol (name ++ '/' : show u)

-- | Declare uninterpreted function of arity 1.
fun1 :: (IsTy a, IsTy b) => Z3 (Expr a -> Expr b)
fun1 = do
    (fd :: FunApp (a -> b)) <- funDecl
    let f e = App $ PApp fd e
    assert $ forall $ \a -> typeInv (f a)
    return f

-- | Declare uninterpreted function of arity 2.
fun2 :: (IsTy a, IsTy b, IsTy c) => Z3 (Expr a -> Expr b -> Expr c)
fun2 = do
    (fd :: FunApp (a -> b -> c)) <- funDecl
    let f e1 e2 = App $ PApp (PApp fd e1) e2
    assert $ forall $ \a b -> typeInv (f a b)
    return f


-- | Declare uninterpreted function of arity 3.
fun3 :: (IsTy a, IsTy b, IsTy c, IsTy d)
     => Z3 (Expr a -> Expr b -> Expr c -> Expr d)
fun3 = do
    (fd :: FunApp (a -> b -> c -> d)) <- funDecl
    let f e1 e2 e3 = App $ PApp (PApp (PApp fd e1) e2) e3
    assert $ forall $ \a b c -> typeInv (f a b c)
    return f

-- | Declare uninterpreted function of arity 4.
fun4 :: (IsTy a, IsTy b, IsTy c, IsTy d, IsTy e)
     => Z3 (Expr a -> Expr b -> Expr c -> Expr d -> Expr e)
fun4 = do
    (fd :: FunApp (a -> b -> c -> d -> e)) <- funDecl
    let f e1 e2 e3 e4 = App $ PApp (PApp (PApp (PApp fd e1) e2) e3) e4
    assert $ forall $ \a b c d -> typeInv (f a b c d)
    return f

-- | Declare uninterpreted function of arity 5.
fun5 :: (IsTy a, IsTy b, IsTy c, IsTy d, IsTy e, IsTy f)
     => Z3 (Expr a -> Expr b -> Expr c -> Expr d -> Expr e -> Expr f)
fun5 = do
    (fd :: FunApp (a -> b -> c -> d -> e -> f)) <- funDecl
    let f e1 e2 e3 e4 e5 = App $ PApp (PApp (PApp (PApp (PApp fd e1) e2) e3) e4) e5
    assert $ forall $ \a b c d e -> typeInv (f a b c d e)
    return f

-- | Declare uninterpreted function
funDecl :: forall a. IsFun a => Z3 (FunApp a)
funDecl = do
  u <- fresh
  smb <- mkIntSymbol u
  dom <- domain (TY :: TY a)
  rng <- range  (TY :: TY a)
  fd  <- mkFuncDecl smb dom rng
  return (FuncDecl fd)

-- | Make assertion in current context.
assert :: Expr Bool -> Z3 ()
assert (Lit True) = return ()
assert e          = compileWithTCC e >>= assertCnstr

-- | Introduce an auxiliary declaration to name a given expression.
--
-- If you really want sharing use this instead of Haskell's /let/.
let_ :: IsTy a => Expr a -> Z3 (Expr a)
let_ e@(Lit _)   = return e
let_ e@(Const _ _) = return e
let_ e = do
  aux <- var
  assert (aux ==* e)
  return aux

-- | Convert an Expr to a string.
exprToString :: Compilable (Expr a) => Expr a -> Z3 String
exprToString e =
  compile e >>= astToString

----------------------------------------------------------------------
-- Models

-- | A computation derived from a model.
newtype Model a = Model { unModel :: ReaderT Base.Model Z3 a }
    deriving (Applicative,Functor,Monad)

-- | Check satisfiability and evaluate a model if some exists.
checkModel :: Model a -> Z3 (Maybe a)
checkModel = checkModelWith (const id)
{-# INLINE checkModel #-}

-- | Check satisfiability and evaluate a model if some exists.
checkModelWith :: (Result -> Maybe a -> b) -> Model a -> Z3 b
checkModelWith f m = uncurry f <$> checkModelWithResult m
{-# INLINE checkModelWith #-}

-- | Check satisfiability and evaluate a model if some exists, also
-- returning a 'Result' to the reason for any failure.
checkModelWithResult :: Model a -> Z3 (Result, Maybe a)
checkModelWithResult m = MonadZ3.withModel $ runReaderT (unModel m)

-- | Show Z3's internal model.
showModel :: Model String
showModel = Model $ ask >>= lift . MonadZ3.showModel

-- | Evaluate an expression within a model.
eval :: forall a. IsTy a => Expr a -> Model a
eval e = Model $ do
  a <- lift $ compileWithTCC e
  lift . fixResult a =<< ask
  where fixResult :: Base.AST -> Base.Model -> Z3 a
        fixResult a m = peek =<< MonadZ3.eval m a

        peek :: Maybe Base.AST -> Z3 a
        peek (Just a) = getValue a
        peek Nothing  = error "Z3.Lang.Prelude.eval: quantified expression or partial model!"

-- | Evaluate a collection of expressions within a model.
evalT :: (IsTy a,Traversable t) => t (Expr a) -> Model (t a)
evalT = T.traverse eval

----------------------------------------------------------------------
-- Expressions

deriving instance Typeable1 Expr

-- In GHC 7.4 Eq and Show are no longer superclasses of Num
#if __GLASGOW_HASKELL__ < 704
deriving instance Show (FunApp a)
deriving instance Show (Expr a)

instance Eq (Expr a) where
  _e1 == _e2 = error "Z3.Lang.Expr: equality not supported"
#endif

instance IsNum a => Num (Expr a) where
  (CRingArith Add as) + (CRingArith Add bs) = CRingArith Add (as ++ bs)
  (CRingArith Add as) + b = CRingArith Add (b:as)
  a + (CRingArith Add bs) = CRingArith Add (a:bs)
  a + b = CRingArith Add [a,b]
  (CRingArith Mul as) * (CRingArith Mul bs) = CRingArith Mul (as ++ bs)
  (CRingArith Mul as) * b = CRingArith Mul (b:as)
  a * (CRingArith Mul bs) = CRingArith Mul (a:bs)
  a * b = CRingArith Mul [a,b]
  (CRingArith Sub as) - b = CRingArith Sub (as ++ [b])
  a - b = CRingArith Sub [a,b]
  negate (CRingArith Sub [a,b]) = CRingArith Sub [b,a]
  negate t = Neg t
  abs e = ite (e >=* 0) e (-e)
  signum e = ite (e >* 0) 1 (ite (e ==* 0) 0 (-1))
  fromInteger = literal . fromInteger

instance IsReal a => Fractional (Expr a) where
  (/) = RealArith Div
  fromRational = literal . fromRational

infixl 7  //, %*, %%
infix  4  ==*, /=*, <*., <=*, >=*, >*
infixr 3  &&*, ||*, `xor`
infixr 2  `implies`, `iff`, ==>, <=>

-- | /literal/ constructor.
literal :: IsTy a => a -> Expr a
literal = Lit

-- | Boolean literals.
true, false :: Expr Bool
true  = Lit True
false = Lit False

-- | Boolean negation
not_ :: Expr Bool -> Expr Bool
not_ = Not

-- | Boolean binary /xor/.
xor :: Expr Bool -> Expr Bool -> Expr Bool
xor = BoolBin Xor

-- | Boolean implication
implies :: Expr Bool -> Expr Bool -> Expr Bool
p `implies` (BoolBin Implies q r)
  = (p &&* q) `implies` r
p `implies` q = BoolBin Implies p q

-- | An alias for 'implies'.
(==>) :: Expr Bool -> Expr Bool -> Expr Bool
(==>) = implies

-- | Boolean /if and only if/.
iff :: Expr Bool -> Expr Bool -> Expr Bool
iff = BoolBin Iff

-- | An alias for 'iff'.
(<=>) :: Expr Bool -> Expr Bool -> Expr Bool
(<=>) = iff

-- | Boolean variadic /and/.
and_ :: [Expr Bool] -> Expr Bool
and_ [] = true
and_ bs = BoolMulti And bs

-- | Boolean variadic /or/.
or_ :: [Expr Bool] -> Expr Bool
or_ [] = false
or_ bs = BoolMulti Or bs

-- | Boolean variadic /distinct/.
distinct :: IsTy a => [Expr a] -> Expr Bool
distinct [] = true
distinct bs = CmpE Distinct bs

-- | Boolean binary /and/.
(&&*) :: Expr Bool -> Expr Bool -> Expr Bool
(BoolMulti And ps) &&* (BoolMulti And qs) = and_ (ps ++ qs)
(BoolMulti And ps) &&* q = and_ (q:ps)
p &&* (BoolMulti And qs) = and_ (p:qs)
p &&* q = and_ [p,q]

-- | Boolean binary /or/.
(||*) :: Expr Bool -> Expr Bool -> Expr Bool
(BoolMulti Or ps) ||* (BoolMulti Or qs) = or_ (ps ++ qs)
(BoolMulti Or ps) ||* q = or_ (q:ps)
p ||* (BoolMulti Or qs) = or_ (p:qs)
p ||* q = or_ [p,q]

-- | Universally quantified formula.
forall  :: QExpr t => t -> Expr Bool
forall f = Quant ForAll f

-- | Existentially quantified formula.
exists  :: QExpr t => t -> Expr Bool
exists f = Quant Exists f

-- | Pattern-based instantiation.
instanceWhen :: Expr Bool -> [Pattern] -> QBody
instanceWhen = QBody

-- | Casting between compatible types
--

cast :: (IsTy a, IsTy b, Castable a b) => Expr a -> Expr b
cast = Cast

instance Castable Integer Rational where
  compileCast _ = mkInt2Real

instance Castable Rational Integer where
  compileCast _ = mkReal2Int


-- | Integer division.
(//) :: IsInt a => Expr a -> Expr a -> Expr a
(//) = IntArith Quot

-- | Integer modulo.
(%*) :: IsInt a => Expr a -> Expr a -> Expr a
(%*) = IntArith Mod

-- | Integer remainder.
(%%) :: IsInt a => Expr a -> Expr a -> Expr a
(%%) = IntArith Rem

-- | @k `divides` n == n %* k ==* 0@
divides :: IsInt a => Expr a -> Expr a -> Expr Bool
k `divides` n = n %* k ==* 0
{-# INLINE divides #-}

-- | Equals.
(==*) :: IsTy a => Expr a -> Expr a -> Expr Bool
e1 ==* e2 = CmpE Eq [e1,e2]

-- | Not equals.
(/=*) :: IsTy a => Expr a -> Expr a -> Expr Bool
e1 /=* e2 = CmpE Distinct [e1,e2]

-- | Less or equals than.
(<=*) :: IsNum a => Expr a -> Expr a -> Expr Bool
(<=*) = CmpI Le

-- | Less than.
(<*.) :: IsNum a => Expr a -> Expr a -> Expr Bool
(<*.) = CmpI Lt

-- | Greater or equals than.
(>=*) :: IsNum a => Expr a -> Expr a -> Expr Bool
(>=*) = CmpI Ge

-- | Greater than.
(>*) :: IsNum a => Expr a -> Expr a -> Expr Bool
(>*) = CmpI Gt

-- | Minimum.
min_ :: IsNum a => Expr a -> Expr a -> Expr a
min_ x y = ite (x <=* y) x y

-- | Maximum.
max_ :: IsNum a => Expr a -> Expr a -> Expr a
max_ x y = ite (x >=* y) x y

-- | /if-then-else/.
ite :: IsTy a => Expr Bool -> Expr a -> Expr a -> Expr a
ite = Ite

----------------------------------------------------------------------
-- Booleans

instance Compilable (Expr Bool) where
  compile = compileBool

instance IsTy Bool where
  typeInv = const true
  tc = tcBool

  mkSort     _  = mkBoolSort
  getValue   v  = maybe False id <$> getBool v
  mkLiteral True  = mkTrue
  mkLiteral False = mkFalse

tcBool :: Expr Bool -> TCM ()
tcBool (Lit _)     = ok
tcBool (Const _ _) = ok
tcBool (Tag _) = ok
tcBool (Not b)     = tcBool b
tcBool (BoolBin Implies e1 e2) = do
  tcBool e1
  withHypo e1 $ tcBool e2
tcBool (BoolBin _op e1 e2) = do
  tcBool e1
  tcBool e2
tcBool (BoolMulti _op es) = mapM_ tcBool es
tcBool (Quant _q _f) = ok
tcBool (CmpE _op es) = do
  mapM_ tc es
tcBool (CmpI _op e1 e2) = do
  tc e1
  tc e2
tcBool (Ite eb e1 e2) = do
  tcBool eb
  withHypo eb $ tcBool e1
  withHypo (Not eb) $ tcBool e2
tcBool (App _app) = ok
tcBool (Cast e) = tc e
tcBool _
    = error "Z3.Lang.Prelude.tcBool: Panic! Impossible constructor in pattern matching!"

compileBool :: Expr Bool -> Z3 AST
compileBool (Lit a)
    = mkLiteral a
compileBool (Const _ u)
    = return u
compileBool (Tag lyt)
    = do ix <- deBruijnIx lyt
         srt <- mkSort (TY :: TY Bool)
         mkBound ix srt
compileBool (Not b)
    = do b'  <- compileBool b
         mkNot b'
compileBool (BoolBin op e1 e2)
    = do e1' <- compileBool e1
         e2' <- compileBool e2
         mkBoolBin op e1' e2'
compileBool (BoolMulti op es)
    = do es' <- mapM compileBool es
         mkBoolMulti op es'
compileBool (Quant q f)
    = compileQuant q [] [] f
compileBool (CmpE op es)
    = do es' <- mapM compile es
         mkEq op es'
compileBool (CmpI op e1 e2)
    = do e1' <- compile e1
         e2' <- compile e2
         mkCmp op e1' e2'
compileBool (Ite b e1 e2)
    = do b'  <- compileBool b
         e1' <- compileBool e1
         e2' <- compileBool e2
         mkIte b' e1' e2'
compileBool (App e)
    = compile e
compileBool (Cast (e :: Expr a))
    = compile e >>= compileCast (TY :: TY (a, Bool))
compileBool _
    = error "Z3.Lang.Prelude.compileBool: Panic! Impossible constructor in pattern matching!"

withSortedSymbol :: IsTy a => TY a -> (Base.Symbol -> Base.Sort -> Z3 b) -> Z3 b
withSortedSymbol t f = do
  u   <- fresh
  sx  <- mkIntSymbol u
  srt <- mkSort t
  f sx srt

instance IsTy a => QExpr (Expr a -> Expr Bool) where
  compileQuant q smbs srts f = do
    withSortedSymbol (TY :: TY a) $ \sx srt ->
      newQLayout $ \x -> do
        body    <- compileBool $ mkBody q x
        mkQuant q [] (sx:smbs) (srt:srts) body
    where mkBody ForAll x = let b = f x in and_ (typeInv x:typecheck b) ==> b
          mkBody Exists x = let b = f x in and_ (b:typeInv x:typecheck b)

data QBody = QBody (Expr Bool) [Pattern]

instance IsTy a => QExpr (Expr a -> QBody) where
  compileQuant q smbs srts f = do
    withSortedSymbol (TY :: TY a) $ \sx srt ->
      newQLayout $ \x -> do
        let QBody body pats = mapFst (mkBody q x) (f x)
        astbody <- compileBool body
        pat_lst <- mkPat pats
        mkQuant q pat_lst (sx:smbs) (srt:srts) astbody
    where mkBody ForAll x b = and_ (typeInv x:typecheck b) ==> b
          mkBody Exists x b = and_ (b:typeInv x:typecheck b)
          mkPat []  = return []
          mkPat lst = mapM compile lst >>= \args -> (:[]) <$> mkPattern args
          mapFst mf (QBody a b) = QBody (mf a) b

instance (IsTy a, QExpr t) => QExpr (Expr a -> t) where
  compileQuant q smbs srts f =
    withSortedSymbol (TY :: TY a) $ \sx srt ->
      newQLayout $ \x ->
        compileQuant q (sx:smbs) (srt:srts) (f x)

----------------------------------------------------------------------
-- Integers

instance Compilable (Expr Integer) where
  compile = compileInteger

instance IsTy Integer where
  typeInv = const true
  tc = tcInteger

  mkSort   _ = mkIntSort
  getValue   = getInt
  mkLiteral  = mkInt

instance IsNum Integer where
instance IsInt Integer where

tcInteger :: Expr Integer -> TCM ()
tcInteger (Lit _) = ok
tcInteger (Const _ _) = ok
tcInteger (Tag _) = ok
tcInteger (Neg e) = tcInteger e
tcInteger (CRingArith _op es) = mapM_ tcInteger es
tcInteger (IntArith _op e1 e2) = do
  newTCC [e2 /=* 0]
  tcInteger e1
  tcInteger e2
tcInteger (Ite eb e1 e2) = do
  tc eb
  withHypo eb $ tcInteger e1
  withHypo (Not eb) $ tcInteger e2
tcInteger (App _) = ok
tcInteger (Cast e) = tc e
tcInteger _
    = error "Z3.Lang.Prelude.tcInteger: Panic! Impossible constructor in pattern matching!"

compileInteger :: Expr Integer -> Z3 AST
compileInteger (Lit a)
  = mkLiteral a
compileInteger (Const _ u)
  = return u
compileInteger (Tag lyt)
  = do ix <- deBruijnIx lyt
       srt <- mkSort (TY :: TY Integer)
       mkBound ix srt
compileInteger (Neg e)
  = mkUnaryMinus =<< compileInteger e
compileInteger (CRingArith op es)
  = mkCRingArith op =<< mapM compileInteger es
compileInteger (IntArith op e1 e2)
  = do e1' <- compileInteger e1
       e2' <- compileInteger e2
       mkIntArith op e1' e2'
compileInteger (Ite eb e1 e2)
  = do eb' <- compile eb
       e1' <- compileInteger e1
       e2' <- compileInteger e2
       mkIte eb' e1' e2'
compileInteger (App e)
    = compile e
compileInteger (Cast (e :: Expr a))
    = compile e >>= compileCast (TY :: TY (a, Integer))
compileInteger _
    = error "Z3.Lang.Prelude.compileInteger: Panic! Impossible constructor in pattern matching!"

----------------------------------------------------------------------
-- Rationals

instance Compilable (Expr Rational) where
  compile = compileRational

instance IsTy Rational where
  typeInv = const true
  tc = tcRational

  mkSort _ = mkRealSort
  getValue   = getReal
  mkLiteral  = mkReal

instance IsNum Rational where
instance IsReal Rational where

tcRational :: Expr Rational -> TCM ()
tcRational (Lit _) = ok
tcRational (Const _ _) = ok
tcRational (Tag _) = ok
tcRational (Neg e) = tcRational e
tcRational (CRingArith _op es) = mapM_ tcRational es
tcRational (RealArith Div e1 e2) = do
  newTCC [e2 /=* 0]
  tcRational e1
  tcRational e2
tcRational (Ite eb e1 e2) = do
  tc eb
  withHypo eb $ tcRational e1
  withHypo (Not eb) $ tcRational e2
tcRational (App _) = ok
tcRational (Cast e) = tc e
tcRational _
    = error "Z3.Lang.Prelude.tcRational: Panic! Impossible constructor in pattern matching!"

compileRational :: Expr Rational -> Z3 AST
compileRational (Lit a)
  = mkLiteral a
compileRational (Const _ u)
  = return u
compileRational (Tag lyt)
  = do ix <- deBruijnIx lyt
       srt <- mkSort (TY :: TY Rational)
       mkBound ix srt
compileRational (Neg e)
  = mkUnaryMinus =<< compileRational e
compileRational (CRingArith op es)
  = mkCRingArith op =<< mapM compileRational es
compileRational (RealArith op@Div e1 e2)
  = do e1' <- compileRational e1
       e2' <- compileRational e2
       mkRealArith op e1' e2'
compileRational (Ite eb e1 e2)
  = do eb' <- compile eb
       e1' <- compileRational e1
       e2' <- compileRational e2
       mkIte eb' e1' e2'
compileRational (App e)
    = compile e
compileRational (Cast (e :: Expr a))
    = compile e >>= compileCast (TY :: TY (a, Rational))
compileRational _
    = error "Z3.Lang.Prelude.compileRational: Panic! Impossible constructor in pattern matching!"

----------------------------------------------------------------------
-- Functions

instance (IsTy a, IsTy b) => IsFun (a -> b) where
  domain _ = (: []) <$> mkSort (TY :: TY a)
  range  _ = mkSort (TY :: TY b)
instance (IsTy a, IsFun (b -> c)) => IsFun (a -> b -> c) where
  domain _ = do
    srt <- mkSort (TY :: TY a)
    lst <- domain (TY :: TY  (b -> c))
    return (srt : lst)
  range  _ = range (TY :: TY (b -> c))

instance IsTy a => Compilable (FunApp a) where
  compile = app2AST

app2AST :: IsTy a => FunApp a -> Z3 Base.AST
app2AST f = doApp2AST f []
  where doApp2AST :: FunApp t -> [Base.AST] -> Z3 Base.AST
        doApp2AST (FuncDecl fd) acc = mkApp fd acc
        doApp2AST (PApp e1 e2)  acc = compile e2 >>= doApp2AST e1 . (: acc)

----------------------------------------------------------------------
-- Patterns

instance Compilable Pattern where
  compile (Pat e) = compile e

