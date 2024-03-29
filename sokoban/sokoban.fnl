(local cell-size 16)

;; Game polish:
;; - Render puzzle in center
;; - Ideally grid would expand as window dimensions changed

(local glyph-player "@")
(local glyph-player-on-storage "+")
(local glyph-box "$")
(local glyph-box-on-storage "*")
(local glyph-storage ".")
(local glyph-wall "#")
(local glyph-empty " ")

(local colors {
   glyph-player [.64 .53 1]
   glyph-player-on-storage [.62 .47 1]
   glyph-box [1 .79 .49]
   glyph-box-on-storage [.59 1 .5]
   glyph-storage [.61 .9 1]
   glyph-wall [1 .58 .82]
   glyph-empty [1 1 1]
})

(local dir-to-offset {
   :left [-1 0]
   :right [1 0]
   :up [0 -1]
   :down [0 1]
})

(local canvas (love.graphics.newCanvas (* 19 cell-size) (* 16 cell-size)))
(var scale 2)
(var level-scale-xform nil)

(var levels [])

(var current-level 1)
(var level [])

(fn set-level [l]
   (set level [])
   (each [y row (ipairs l)]
      (tset level y {})
      (each [x cell (ipairs row)]
         (tset (. level y) x cell))))

(fn level-bounds [l]
   (var max-x 0)
   (each [y row (ipairs l)]
      (set max-x (math.max max-x (# row))))
   [max-x (# l)])

(fn load-level []
   (let [next-level (. levels current-level)
         [mx my] (level-bounds next-level)
         [dx dy] [(- 19 mx) (- 16 my)]
         xform (love.math.newTransform)]

      (: xform :translate (* 4 dx) (* 4 dy))
      (set level-scale-xform xform)

      (set-level next-level)))

(fn next-level []
   (set current-level (+ 1 (% current-level (# levels))))
   (load-level))

(fn prev-level []
   (set current-level (+ 1 (% (- current-level 2) (# levels))))
   (load-level))

;; Max level size is [19 16]

(fn love.load []
   ;; Setup the canvas
   (: canvas :setFilter "nearest" "nearest")

   ;; Set the graphics state
   (love.graphics.setBackgroundColor 1 1 .75)

   ;; Load the levels and initialize the game
   (set levels (require :levels))
   (load-level))

(fn draw-cell [x y glyph]
   (let [px (* (- x 1) cell-size)
         py (* (- y 1) cell-size)]
      (love.graphics.setColor (. colors glyph))
      (love.graphics.rectangle :fill px py cell-size cell-size)
      (love.graphics.setColor 1 1 1)
      (love.graphics.print glyph px py)))

(fn get-cell [x y]
   (. (. level y) x))

(fn get-cell-safe [x y]
   (let [row (. level y)]
      (when (~= nil row)
         (. row x))))

(fn set-cell [x y v]
   (tset (. level y) x v))

(fn draw-game []
   (love.graphics.applyTransform level-scale-xform)
   (each [y row (ipairs level)]
      (each [x cell (ipairs row)]
         (if (~= cell " ")
            (draw-cell x y (get-cell x y))))))

(fn love.draw []
   (love.graphics.setCanvas canvas)
   (love.graphics.clear)
   (love.graphics.setColor 1 1 1)
   (draw-game)
   (love.graphics.setCanvas)
   (love.graphics.setColor 1 1 1)
   (love.graphics.draw canvas 0 0 0 scale scale))

(fn find-player []
   (var playerX 0)
   (var playerY 0)
   (each [testY row (ipairs level)]
      (each [testX cell (ipairs row)]
         (when (or (= cell glyph-player) (= cell glyph-player-on-storage))
            (set playerX testX)
            (set playerY testY))))
   [playerX playerY])

;; when moving update the current spot the player is at based on the target
;; of their movement
(local next-current {
   glyph-player glyph-empty
   glyph-player-on-storage glyph-storage
})

;; when moving update the target spot the player is moving based on its contents
(local next-adjacent {
   glyph-empty glyph-player
   glyph-storage glyph-player-on-storage
})

(local next-adjacent-push {
   glyph-box glyph-player
   glyph-box-on-storage glyph-player-on-storage
})

(local next-beyond {
   glyph-empty glyph-box
   glyph-storage glyph-box-on-storage
})

(fn level-clear? []
   (var clear true)
   (each [y row (ipairs level)]
      (each [x cell (ipairs row)]
         (when (= cell glyph-box)
            (set clear false))))
   clear)

(fn love.keypressed [key]

   ;; quit the game
   (when (= key :escape)
      (love.event.quit))

   ;; reload the level
   (when (= key :r)
      (load-level))

   (if (= key :n)
      (next-level)
      (= key :p)
      (prev-level))

   (when (or (= key :up) (= key :down) (= key :left) (= key :right))
      (let [[px py] (find-player)
            current (get-cell px py)
            [dx dy] (. dir-to-offset key)
            [ax ay] [(+ px dx) (+ py dy)]
            adjacent (get-cell ax ay)
            [bx by] [(+ px dx dx) (+ py dy dy)]
            beyond (get-cell-safe bx by)]

         ;; player tries to move
         (when (~= nil (. next-adjacent adjacent))
            (set-cell px py (. next-current current))
            (set-cell ax ay (. next-adjacent adjacent)))

         ;; player tries to push a box
         (when (and (~= nil (. next-adjacent-push adjacent)) (~= nil (. next-beyond beyond)))
            (set-cell px py (. next-current current))
            (set-cell ax ay (. next-adjacent-push adjacent))
            (set-cell bx by (. next-beyond beyond)))

         (when (level-clear?)
            (next-level))

         (print px py dx dy current adjacent))))
