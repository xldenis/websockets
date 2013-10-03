--------------------------------------------------------------------------------
-- | This provides a simple stand-alone server for 'WebSockets' applications.
-- Note that in production you want to use a real webserver such as snap or
-- warp.
{-# LANGUAGE OverloadedStrings #-}
module Network.WebSockets.Server
    ( ServerApp
    , runServer
    ) where


--------------------------------------------------------------------------------
import           Control.Concurrent            (forkIO)
import           Control.Monad                 (forever)
import           Network.Socket                (Socket)
import qualified Network.Socket                as S
import qualified System.IO.Streams.Attoparsec  as Streams
import qualified System.IO.Streams.Builder     as Streams
import qualified System.IO.Streams.Network     as Streams


--------------------------------------------------------------------------------
import           Network.WebSockets.Connection
import           Network.WebSockets.Finalizer
import           Network.WebSockets.Http


--------------------------------------------------------------------------------
-- | WebSockets application that can be ran by a server
type ServerApp = PendingConnection -> IO ()


--------------------------------------------------------------------------------
-- | Provides a simple server. This function blocks forever. Note that this
-- is merely provided for quick-and-dirty standalone applications, for real
-- applications, you should use a real server.
runServer :: String     -- ^ Address to bind
          -> Int        -- ^ Port to listen on
          -> ServerApp  -- ^ Application
          -> IO ()      -- ^ Never returns
runServer host port app = S.withSocketsDo $ do
    sock  <- S.socket S.AF_INET S.Stream S.defaultProtocol
    _     <- S.setSocketOption sock S.ReuseAddr 1
    host' <- S.inet_addr host
    S.bindSocket sock (S.SockAddrInet (fromIntegral port) host')
    S.listen sock 5
    _ <- forever $ do
        -- TODO: top level handle
        (conn, _) <- S.accept sock
        _         <- forkIO $ runApp conn app
        return ()
    S.sClose sock


--------------------------------------------------------------------------------
runApp :: Socket
       -> ServerApp
       -> IO ()
runApp socket app = do
    finalizer   <- mkFinalizer (S.sClose socket)
    (sIn, sOut) <- Streams.socketToStreams socket
    bOut        <- Streams.builderStream sOut
    -- TODO: we probably want to send a 40x if the request is bad?
    request     <- Streams.parseFromStream (decodeRequestHead False) sIn
    let pc = PendingConnection
                { pendingRequest   = request
                , pendingIn        = sIn
                , pendingOut       = bOut
                , pendingFinalizer = finalizer
                }

    app pc