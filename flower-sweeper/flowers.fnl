;; GAME PARAMS

(local grid-width 19)
(local grid-height 14)

(local bomb-count 40)

;; APP STATE

;; TODO simplify this
(local tile-import-size 40)
(local tile-draw-size 40)

(local font (love.graphics.newFont "lilliput-steps.ttf" 28))

(local image (love.graphics.newImage "tiles.png"))
(local tile-quads [])

;; these names correspond to the section of `image` specified by quad at the
;; index in `tile-quads`
(local tile-names {
   :covered 1
   :covered-hover 2
   :uncovered 3
   :flower 4
   :flag 5
   :? 6
   :flag-countdown 7
   :flagged-bomb 8
})

;; GAME STATE

(local grid {})

(var countdown-mode? true)

(var selected-x 0)
(var selected-y 0)

;; TODO promote this to game-state w/ values :init, :playing, :win, :lose
;; and have a fn (game-over?) that is true if state is one of the last two.
(var game-over? false)


(fn tile-for-number [n]
   (. tile-quads (+ n 8)))

(fn tile-quad [name]
   (. tile-quads (. tile-names name)))

(fn number? [arg]
   (= (type arg) :number))

;; TODO this is kind of gross
;; actually the whole flower drawing system is kinda gross
;; TODO this could be further improved by returning the quad and
;; letting another function draw
(fn draw-tile [name x y]
   (var quad nil)

   (if
      (number? name)
      (set quad (tile-for-number name))

      (and countdown-mode? (= name :flag))
      (set quad (tile-quad :flag-countdown))

      :else
      (set quad (tile-quad name)))

   (love.graphics.draw image quad x y))

;; This is the final TODO list, no more items can be added unless they are bugs.
;; - Consider improving the graphics of 4 & 5
;; - Redo the drawing system
;; - Really a victory mode in general so you know you've won!
;; - Also a counter with remaining unflagged bombs
;; - INITIAL BOMB PLACEMENT CANNOT KILL YOU!
;; - Rename flower to bomb in the code
;; - Add the font, get the size right, add a "status bar" with:
;;    [COUNTODWN] (in yellow) when in countodwn mode
;;    Number of boms remaining
;;    And a win or lose message
;; E.g.
;;  CLICK ANYWHERE TO BEGIN
;;  [COUNTDOWN MODE] 40 BOMBS REMAIN
;;  [NORMAL MODE] 08 BOMBS REMAIN
;;  CONGRATULATIONS, YOU WON!
;;  32 (8 FLAGGED DISARMED) BOMBS EXPLODE! CLICK ANYWHERE TO START AGAIN.

(fn icells []
   "Iterates over all the points in the grid as (x, y, cell)."
   (let [co (coroutine.create (fn []
      (each [y row (ipairs grid)]
         (each [x cell (ipairs row)]
            (coroutine.yield x y cell)))))]
      (fn []
         (let [(ok x y cell) (coroutine.resume co)]
            (when ok
               (values x y cell))))))

(fn ineighbors [x y]
   "Iterates over all the valid neighbors of point (x, y) as (nx, ny, cell)."
   (let [co (coroutine.create (fn []
      (for [dx -1 1]
         (for [dy -1 1]
            (when (not (and (= dx 0) (= dy 0)))
               (let [[nx ny] [(+ x dx) (+ y dy)]
                     cell (-?> grid (. ny) (. nx))]
                  (if cell
                     (coroutine.yield nx ny cell))))))))]
      (fn []
         (let [(ok nx ny cell) (coroutine.resume co)]
            (when ok (values nx ny cell))))))

(fn init-grid! []
   (set game-over? false)

   ;; prepare blank grid
   (for [y 1 grid-height]
      (tset grid y {})
      (for [x 1 grid-width]
         (tset grid y x {:flower false :state :covered})))

   ;; place flowers at random locations
   (var possible-flowers [])
   (for [x 1 grid-width]
      (for [y 1 grid-height]
         (table.insert possible-flowers {:x x :y y})))

   (for [i 1 bomb-count]
      (let [ndx (love.math.random (# possible-flowers))
            {: x : y} (table.remove possible-flowers ndx)]
         (tset grid y x :flower true))))

(fn load-images! []
   (for [i 0 15]
      (let [[w h] [tile-import-size tile-import-size]
            row (math.floor (/ i 8))
            col (% i 8)
            [x y] [(* col w) (* row h)]
            quad (love.graphics.newQuad x y w h (image:getDimensions))]
         (table.insert tile-quads quad))))

(fn love.load []
   (load-images!)
   ;; TODO init-blank-grid, call (init-grid first-guess) later
   (init-grid!))

(fn draw-tiles-atlas []
   (let [padding 22]
      (each [i quad (ipairs tile-quads)]
         (love.graphics.draw image quad (* padding (- i 1)) 0))))

(fn love.keypressed [key]
   ;; quit the game
   (when (= key :escape)
      (love.event.quit))

   ;; reset the game
   (when (= key :r)
      (init-grid!))

   ;; toggle countdown mode
   (when (= key :c)
      (set countdown-mode? (not countdown-mode?))))

(fn surrounding-flowers [x y]
   (var count 0)
   (each [nx ny cell (ineighbors x y)]
      (when (and countdown-mode? (= cell.state :flag))
         (set count (- count 1)))
      (when cell.flower
         (set count (+ count 1))))
   count)

(fn flood-uncover [x y]
   (local stack [[x y]])
   (while (> (# stack) 0)
      (let [[x y] (table.remove stack)]
         (tset grid y x :state :uncovered)
         (when (= (surrounding-flowers x y) 0)
            (each [nx ny cell (ineighbors x y)]
               (when (or (= cell.state :covered) (= cell.state :?))
                  (table.insert stack [nx ny])))))))

(fn flood-uncover-flag [x y]
   "Marking a flag in countdown mode causes adjacent spaces that now show
    a count of 0 to have their neighbors revealed. This could cause the
    a bomb to be revealed and the player to lose the game if a flag location
    is placed incorrectly."
   (each [nx ny cell (ineighbors x y)]
      (when (and (= cell.state :uncovered)
                 (= (surrounding-flowers nx ny) 0))
         (flood-uncover nx ny))))

(local covered-cell-transitions {
   :covered :flag
   :flag :?
   :? :covered
})

(fn check-game-won []
   (var done true)
   (for [y 1 grid-height]
      (for [x 1 grid-width]
         (let [cell (. grid y x)]
            (if (and (not cell.flower) (~= cell.state :uncovered))
               (set done false)))))
   done)

(fn love.mousereleased [x y button]
   (when (not game-over?)
      (let [cell (. grid selected-y selected-x)]

         (when (= button 1)
            (if (~= cell.state :flag)
               (if cell.flower (set game-over? true)
                  :else
                  (flood-uncover selected-x selected-y))))

         (when (= button 2)
            (let [next (. covered-cell-transitions cell.state)]
               (when next
                  (tset grid selected-y selected-x :state next))
                  (when (and countdown-mode? (= next :flag))
                     (flood-uncover-flag selected-x selected-y))))))

   (if (check-game-won)
      (set game-over? true)))

(fn love.update []
   (let [(x y) (love.mouse.getPosition)]
      (set selected-x (math.min grid-width
         (math.floor (+ 1 (/ x tile-draw-size)))))
      (set selected-y (math.min grid-height
         (math.floor (+ 1 (/ y tile-draw-size)))))))

(fn count-flags []
   (var count 0)
   (each [_ _ cell (icells)]
      (if (= cell.state :flag)
         (set count (+ count 1))))
   count)

(fn draw-status-bar []
   (var line "")

   ;; 20 FLAGS / 40 BOMBS                  [COUNTDOWN]
   ;;

   (if countdown-mode?
      (set line (.. line "[COUNTDOWN] "))
      :else
      (set line (.. line "[NORMAL] ")))

   (set line (.. line (count-flags) " FLAGS / " bomb-count " BOMBS"))

   (love.graphics.print line 0 557))

(fn draw-tile-for-cell [x y cell]
   (let [selected? (and (= x selected-x) (= y selected-y))
         clicking? (love.mouse.isDown 1)
         adjacent-flowers (surrounding-flowers x y)]

      (if

         ;; COVERED => mouse hover -> :covered-hover, else -> :covered
         (= cell.state :covered)
         (if (and selected? (not game-over?)) :covered-hover
             :else :covered)

         ;; FLAG => mouse down -> :covered, else -> :flag
         (= cell.state :flag)
         (if (and selected? clicking?)
            :covered
            :else
            :flag)

         ;; QUESTION => mouse down -> :uncovered, else -> :?
         (= cell.state :?)
         (if (and selected? clicking?)
            :uncovered
            :else
            :?)

         ;; UNCOVERED =>
         ;;    flower? -> :flower
         ;;    adjacent bombs? -> count
         ;;    else -> :uncovered
         (= cell.state :uncovered)
         (if cell.flower
            :flower
            (> adjacent-flowers 0)
            adjacent-flowers
            :else
            :uncovered))))

(fn love.draw []
   (love.graphics.setFont font)

   (each [x y cell (icells)]
      (let [cell (. grid y x)]
         (var tile (draw-tile-for-cell x y cell))

         ;; draw all bombs when game is over
         (when (and game-over? cell.flower)
            (if (= cell.state :flag)
               (set tile :flagged-bomb)
               :else
               (set tile :flower)))

         (draw-tile
            tile
            (* (- x 1) tile-draw-size)
            (* (- y 1) tile-draw-size))))

   (draw-status-bar))
