{-# LANGUAGE DeriveAnyClass #-}

module Network.P2P.Message
  ( messagingProc

  , issueTransfer
  , mineBlock
  ) where

import Protolude

import Control.Distributed.Process
  ( Process
  , NodeId

  , getSelfNode
  , getSelfPid
  , send
  , nsendRemote
  , receiveWait
  , match
  , register
  , matchAny
  , say
  )

import Data.Binary (Binary)

import Network.P2P.Node

import Address (Address)
import Block (Block, index)
import qualified Block (mineBlock)
import Cryptography (Hash)
import Transaction (Transaction, transferTransaction, hashTransaction)

--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------

data GetBlockMsg = GetBlockMsg
  { blockIndex :: Int    -- ^ Index of the block desired
  , replyTo    :: NodeId -- ^ Which node is querying for the block
  } deriving (Show, Generic, Binary)

data BlockMsg = BlockMsg
  { block  :: Block  -- ^ Block being sent to peer
  , sender :: NodeId -- ^ Which process is sending the block
  } deriving (Show, Generic, Binary)

data TransactionMsg = TransactionMsg
  { transaction :: Transaction
  } deriving (Show, Generic, Binary)

mkGetBlockMsg :: Int -> Process GetBlockMsg
mkGetBlockMsg n = GetBlockMsg n <$> getSelfNode

mkBlockMsg :: Block -> Process BlockMsg
mkBlockMsg b = BlockMsg b <$> getSelfNode

--------------------------------------------------------------------------------
-- Messaging Process
--------------------------------------------------------------------------------

-- | The name of a node's messaging process
messaging :: [Char]
messaging = "messaging"

messagingProc :: NodeEnv -> Process ()
messagingProc nodeEnv = do
  register messaging =<< getSelfPid
  latestBlock <- liftIO (askLatestBlock nodeEnv)
  nsendPeers nodeEnv =<< mkGetBlockMsg (index latestBlock + 1)
  forever $ receiveWait
    [ match handleBlockMsg
    , match handleGetBlockMsg
    , match handleTransactionMsg
    ]
  where
    -- When receiving a 'BlockMsg':
    --   - Attempt to apply the new block to the node state
    --   - If successful
    --       - prune the transaction pool
    --       - query the sending node for more blocks
    --   - Else
    --       - report the error
    --
    --  helper functions:
    --    - Network.P2P.Node.addBlock
    --    - Network.P2P.Node.pruneTxPool
    --    - mkGetBlockMsg
    --    - nsendRemote
    handleBlockMsg :: BlockMsg -> Process ()
    handleBlockMsg = undefined

    -- When receiving a 'GetBlockMsg':
    --   - Query the current node state for the block at the queried index
    --   - If a block with that index exists, send it back to the querying node
    --
    --  helper functions:
    --    - Network.P2P.Node.askBlock
    --    - mkBlockMsg
    --    - nsendRemote
    handleGetBlockMsg :: GetBlockMsg -> Process ()
    handleGetBlockMsg = undefined

    -- When receiving a 'TransactionMsg':
    --   - Attempt to add the transaction to the mempool
    --   - On failure, log the error
    --
    -- helper functions:
    --   - Network.P2P.Node.addTxPool
    --   - Control.Distributed.Process.say
    handleTransactionMsg :: TransactionMsg -> Process ()
    handleTransactionMsg = undefined

--------------------------------------------------------------------------------
-- Network Actions
--------------------------------------------------------------------------------

-- | Issue a transfer transaction and send it to all peers
issueTransfer :: NodeEnv -> Address -> Int -> Process Hash
issueTransfer nodeEnv to amount = do
  let sk = privateKey (nodeConfig nodeEnv)
  tx <- liftIO (transferTransaction sk to amount)
  nsendPeers nodeEnv (TransactionMsg tx)
  pure (hashTransaction tx)

-- | Mine a block and send it to all peers
mineBlock :: NodeEnv -> Process Int
mineBlock nodeEnv = do
  let sk = privateKey (nodeConfig nodeEnv)
  block <- liftIO $ do
    latestBlock <- askLatestBlock nodeEnv
    validTxs    <- fst <$> pruneTxPool nodeEnv
    Block.mineBlock sk latestBlock validTxs
  nsendPeers nodeEnv =<< mkBlockMsg block
  pure (index block)

-- | Send a message to all known peers
nsendPeers :: (Binary a, Typeable a) => NodeEnv -> a -> Process ()
nsendPeers nodeEnv msg = do
  peers <- liftIO (askPeers nodeEnv)
  forM_ peers $ \(Peer nid) -> do
    say $ "Sending msg to " <> show nid
    nsendRemote nid messaging msg
