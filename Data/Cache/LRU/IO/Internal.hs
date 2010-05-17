{-# OPTIONS_HADDOCK not-home #-}

-- | This module contains a mutable wrapping of an LRU in the IO
-- monad, providing atomic access in a concurrent environment.  All
-- calls preserve the same semantics as those in "Data.Cache.LRU", but
-- perform updates in place.
--
-- This module contains the internal implementation details.  It's
-- possible to put an 'AtomicLRU' into a bad state with this module.
-- It is highly recommended that the external interface,
-- "Data.Cache.LRU.IO", be used instead.
module Data.Cache.LRU.IO.Internal where

import Prelude hiding ( lookup, mod, take )

import Control.Applicative ( (<$>) )
import Control.Concurrent.MVar ( MVar )
import qualified Control.Concurrent.MVar as MV

import Control.Exception ( bracketOnError )

import Data.Cache.LRU ( LRU )
import qualified Data.Cache.LRU as LRU

-- | The opaque wrapper type
newtype AtomicLRU key val = C (MVar (LRU key val))

-- | Make a new AtomicLRU that will not grow beyond the optional
-- maximum size, if specified.
newAtomicLRU :: Ord key => Maybe Integer -- ^ the optional maximum size
             -> IO (AtomicLRU key val)
newAtomicLRU = fmap C . MV.newMVar . LRU.newLRU

-- | Build a new LRU from the optional maximum size and list of
-- contents. See 'LRU.fromList' for the semantics.
fromList :: Ord key => Maybe Integer -- ^ the optional maximum size
            -> [(key, val)] -> IO (AtomicLRU key val)
fromList s l = fmap C . MV.newMVar $ LRU.fromList s l

-- | Retrieve a list view of an AtomicLRU.  See 'LRU.toList' for the
-- semantics.
toList :: Ord key => AtomicLRU key val -> IO [(key, val)]
toList (C mvar) = LRU.toList <$> MV.readMVar mvar

maxSize :: AtomicLRU key val -> IO (Maybe Integer)
maxSize (C mvar) = LRU.maxSize <$> MV.readMVar mvar

-- | Insert a key/value pair into an AtomicLRU.  See 'LRU.insert' for
-- the semantics.
insert :: Ord key => key -> val -> AtomicLRU key val -> IO ()
insert key val (C mvar) = modifyMVar_' mvar $ return . LRU.insert key val

-- | Look up a key in an AtomicLRU. See 'LRU.lookup' for the
-- semantics.
lookup :: Ord key => key -> AtomicLRU key val -> IO (Maybe val)
lookup key (C mvar) = modifyMVar' mvar $ return . LRU.lookup key

-- | Remove an item from an AtomicLRU.  Returns the value for the
-- removed key, if it was present
delete :: Ord key => key -> AtomicLRU key val -> IO (Maybe val)
delete key (C mvar) = modifyMVar' mvar $ return . LRU.delete key

-- | Remove the least-recently accessed item from an AtomicLRU.
-- Returns the (key, val) pair removed, if one was present.
pop :: Ord key => AtomicLRU key val -> IO (Maybe (key, val))
pop (C mvar) = modifyMVar' mvar $ return . LRU.pop

-- | Returns the number of elements the AtomicLRU currently contains.
size :: AtomicLRU key val -> IO Int
size (C mvar) = LRU.size <$> MV.readMVar mvar

-- | A version of 'MV.modifyMVar_' that forces the result of the
-- function application to WHNF.
modifyMVar_' :: MVar a -> (a -> IO a) -> IO ()
modifyMVar_' mvar f = do
  let take = MV.takeMVar mvar
      replace = MV.putMVar mvar
      mod x = do
        x' <- f x
        MV.putMVar mvar $! x'

  bracketOnError take replace mod

-- | A version of 'MV.modifyMVar' that forces the result of the
-- function application to WHNF.
modifyMVar' :: MVar a -> (a -> IO (a, b)) -> IO b
modifyMVar' mvar f = do
  let take = MV.takeMVar mvar
      replace = MV.putMVar mvar
      mod x = do
        (x', result) <- f x
        MV.putMVar mvar $! x'
        return result

  bracketOnError take replace mod
