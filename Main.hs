{-# LANGUAGE Arrows #-}
module Main where

import FRP.Yampa
import FRP.Yampa.Utilities
import Graphics.UI.GLUT hiding (Level)

import Data.IORef
import Control.Arrow
import Data.Monoid

import GLAdapter

-- | Event Definition:

data Input = Keyboard { key       :: Key,
                        keyState  :: KeyState,
                        modifiers :: Modifiers }
-- | Rendering Code:

data Point3D = P3D { x :: Integer, y :: Integer, z :: Integer }

-- size is unncessary!!
data Level = Level { startingPoint :: Point3D, obstacles :: [Point3D] }

size :: Level -> Integer
size = (+1) . maximum . map (\(P3D x y z) -> maximum [x,y,z]) . obstacles

data GameState = Game { rotX      :: Double, 
                        rotY      :: Double, 
                        playerPos :: Point3D }

type R = Double

testLevel = Level (P3D 0 0 1) [P3D 0 0 0, P3D 5 5 5, P3D 0 5 1]

xAxis = Vector3 1 0 0 :: Vector3 R 
yAxis = Vector3 0 1 0 :: Vector3 R
zAxis = Vector3 0 0 1 :: Vector3 R 

initGL :: IO (Event Input)
initGL = do
    getArgsAndInitialize
    createWindow "AnaCube!"
    initialDisplayMode $= [ WithDepthBuffer ]
    depthFunc          $= Just Less
    clearColor         $= Color4 0 0 0 0
    light (Light 0)    $= Enabled
    lighting           $= Enabled 
    blend              $= Enabled
    blendFunc          $= (SrcAlpha, OneMinusSrcAlpha) 
    colorMaterial      $= Just (FrontAndBack, AmbientAndDiffuse)
    reshapeCallback    $= Just resizeScene
    return NoEvent

renderGame :: Level -> GameState -> IO ()
renderGame l (Game rotX rotY pPos) = do
    loadIdentity
    translate $ Vector3 (0 :: R) 0 (-1.5*(fromInteger $ size l))
    rotate (rotX * 10) xAxis
    rotate (rotY * 10) yAxis
    color $ Color3 (1 :: R) 1 1
    position (Light 0) $= Vertex4 0 0 0 1  
    lightModelAmbient $= Color4 0.5 0.5 0.5 1 
    diffuse (Light 0) $= Color4 1 1 1 1
    renderObject Wireframe (Cube $ fromInteger $ size l)
    renderPlayer $ startingPoint l
    mapM_ renderObstacle $ obstacles l
    flush
    where size2 :: R
          size2 = (fromInteger $ size l)/2
          green = Color4 0.8 1.0 0.7 0.9 :: Color4 R
          red   = Color4 1.0 0.7 0.8 1.0 :: Color4 R 
          renderShapeAt s p3D = preservingMatrix $ do
            translate $ Vector3 (0.5 - size2 + (fromInteger $ x p3D)) 
                                (0.5 - size2 + (fromInteger $ y p3D)) 
                                (0.5 - size2 + (fromInteger $ z p3D))
            renderObject Solid s
          renderObstacle = (color green >>) . (renderShapeAt $ Cube 1)
          renderPlayer   = (color red >>) . (renderShapeAt $ Sphere' 0.5 20 20)

keyDowns :: SF (Event Input) (Event Input)
keyDowns = arr $ filterE ((==Down) . keyState)

countHold :: SF (Event a) Integer
countHold = count >>> hold 0

game :: SF GameState (IO ())
game = arr $ (\gs -> do
        clear [ ColorBuffer, DepthBuffer ]
        renderGame testLevel gs
        flush)

-- | Input
parseInput :: SF (Event Input) GameState
parseInput = proc i -> do
    down  <- keyDowns     -< i
    ws    <- countKey 'w' -< down
    as    <- countKey 'a' -< down
    ss    <- countKey 's' -< down
    ds    <- countKey 'd' -< down
    upEvs <- arr (filterE ((==(SpecialKey KeyUp)) . key)) -< down
    speed <- constant 1 -< upEvs

    returnA -< Game { rotX      = (fromInteger $ (ws - ss)),
                      rotY      = (fromInteger $ (ds - as)),
                      playerPos = P3D 0 0 speed              }

    where countKey c = filterE ((==(Char c)) . key) ^>> countHold

-- | Main, initializes Yampa and sets up reactimation loop
main :: IO ()
main = do
    newInput <- newIORef NoEvent
    rh <- reactInit initGL (\_ _ b -> b >> return False) 
                    (parseInput >>> game)
    displayCallback $= return ()
    keyboardMouseCallback $= Just 
        (\k ks m _ -> writeIORef newInput (Event $ Keyboard k ks m))
    idleCallback $= Just (idle newInput rh) 
    mainLoop

-- | Reactimation iteration, supplying the input
idle :: IORef (Event Input) -> ReactHandle (Event Input) (IO ()) -> IO ()
idle newInput rh = do
    newInput' <- readIORef newInput
    react rh (1, Just newInput')
    return ()
    
