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
   :bomb 4
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

;; game states:
;; :init - board is empty awaiting first click
;; :play - bombs have been placed, player is revealing tiles
;; :lost - a bomb was revealed
;; :won  - all non-bomb tiles have been revealed
(var game-state :init)

(fn game-over? []
   (or (= game-state :won) (= game-state :lost)))


(fn tile-for-number [n]
   (. tile-quads (+ n 8)))

(fn tile-quad [name]
   (. tile-quads (. tile-names name)))

(fn number? [arg]
   (= (type arg) :number))

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
;; - Move the flag part of the flagged bomb image higher
;; - Redo the drawing system

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

(fn load-images! []
   (for [i 0 15]
      (let [[w h] [tile-import-size tile-import-size]
            row (math.floor (/ i 8))
            col (% i 8)
            [x y] [(* col w) (* row h)]
            quad (love.graphics.newQuad x y w h (image:getDimensions))]
         (table.insert tile-quads quad))))

(fn init-game! []
   (set game-state :init)

   ;; prepare blank grid
   (for [y 1 grid-height]
      (tset grid y {})
      (for [x 1 grid-width]
         (tset grid y x {:bomb false :state :covered}))))

(fn place-bombs! [player-x player-y]
   "Fill the grid with hidden bombs while avoiding the space [player-x player-y]"
   (set game-state :play)
   (var possible-bombs [])
   (for [x 1 grid-width]
      (for [y 1 grid-height]
         (when (and (~= x player-x) (~= y player-y))
            (table.insert possible-bombs {:x x :y y}))))

   (for [i 1 bomb-count]
      (let [ndx (love.math.random (# possible-bombs))
            {: x : y} (table.remove possible-bombs ndx)]
         (tset grid y x :bomb true))))

(fn love.load []
   (load-images!)
   (init-game!))

(fn love.keypressed [key]
   ;; quit the game
   (when (= key :escape)
      (love.event.quit))

   ;; reset the game
   (when (= key :r)
      (init-game!))

   ;; toggle countdown mode
   (when (= key :c)
      (set countdown-mode? (not countdown-mode?))))

(fn surrounding-bombs [x y]
   (var count 0)
   (each [nx ny cell (ineighbors x y)]
      (when (and countdown-mode? (= cell.state :flag))
         (set count (- count 1)))
      (when cell.bomb
         (set count (+ count 1))))
   count)

(fn flood-uncover [x y]
   (local stack [[x y]])
   (while (> (# stack) 0)
      (let [[x y] (table.remove stack)]
         (tset grid y x :state :uncovered)
         (when (= (surrounding-bombs x y) 0)
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
                 (= (surrounding-bombs nx ny) 0))
         (flood-uncover nx ny))))

(local covered-cell-transitions {
   :covered :flag
   :flag :?
   :? :covered
})


(fn check-game-over! []
   "Check for a game over condition and potentially update the game state.
    The game is won when all non-bomb cells have been uncovered. The game is
    lost when a bomb cell has been uncovered."

   (var all-empty-spaces-uncovered true)
   (var all-bombs-covered true)

   (each [x y cell (icells)]
      ;; if there is a covered non-bomb cell the game has not been won
      ;; if there is an uncovered bomb cell the game has been lost
      (if (and cell.bomb (= cell.state :uncovered))
         (set all-bombs-covered false)

         (and (not cell.bomb) (= cell.state :covered))
         (set all-empty-spaces-uncovered false)))

   (if (not all-bombs-covered)
      (set game-state :lost)

      all-empty-spaces-uncovered
      (set game-state :won)))

(fn love.mousereleased [x y button]
   (when (= game-state :init)
      (when (= button 1)
         (place-bombs! selected-x selected-y)
         (flood-uncover selected-x selected-y)))

   (when (= game-state :play)
      (let [cell (. grid selected-y selected-x)]

         (when (= button 1)
            (if (~= cell.state :flag)
               (if cell.bomb
                  (set cell.state :uncovered)
                  :else
                  (flood-uncover selected-x selected-y))))

         (when (= button 2)
            (let [next (. covered-cell-transitions cell.state)]
               (when next
                  (tset grid selected-y selected-x :state next))
                  (when (and countdown-mode? (= next :flag))
                     (flood-uncover-flag selected-x selected-y))))))

   (check-game-over!))

(fn love.update []
   (let [(x y) (love.mouse.getPosition)]
      (set selected-x (math.min grid-width
         (math.floor (+ 1 (/ x tile-draw-size)))))
      (set selected-y (math.min grid-height
         (math.floor (+ 1 (/ y tile-draw-size)))))))

;; TODO make a count-cells routine that takes a predicate, e.g.:
;; (count-cells #(= $.state :flag))
(fn count-flags []
   (var count 0)
   (each [_ _ cell (icells)]
      (when (= cell.state :flag)
         (set count (+ count 1))))
   count)

(fn count-unflagged-bombs []
   (var count 0)
   (each [_ _ cell (icells)]
      (when (and cell.bomb (~= cell.state :flag))
         (set count (+ count 1))))
   count)

(fn draw-status-bar []
   (var line "")

   (when (= game-state :init)
      (set line "LEFT CLICK ANY TILE TO BEGIN..."))

   (when (= game-state :play)
      (if countdown-mode?
         (set line (.. line "[COUNTDOWN] "))
         :else
         (set line (.. line "[NORMAL] ")))

      (set line (.. line (count-flags) " FLAGS / " bomb-count " BOMBS")))

   ;; LINE WIDTH IS 38 CHARACTERS D:
   ;; --------------------------------------
   ;; VICTORY, ALL BOMBS DISARMED! [R]ESTART
   ;; DEFEAT! 20 BOMBS EXPLODE. [R]ESTART

   (when (= game-state :lost)
      (set line (.."DEFEAT! " (count-unflagged-bombs) " BOMBS EXPLODE. [R]ESTART")))

   (when (= game-state :won)
      (set line "VICTORY! ALL BOMBS DISARMED! [R]ESTART"))

   (love.graphics.print line 6 557))

(fn draw-tile-for-cell [x y cell]
   (let [selected? (and (= x selected-x) (= y selected-y))
         clicking? (love.mouse.isDown 1)
         adjacent-bombs (surrounding-bombs x y)]

      (if

         ;; COVERED => mouse hover -> :covered-hover, else -> :covered
         (= cell.state :covered)
         (if (and selected? (not (game-over?))) :covered-hover
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
         ;;    bomb? -> :bomb
         ;;    adjacent bombs? -> count
         ;;    else -> :uncovered
         (= cell.state :uncovered)
         (if cell.bomb
            :bomb
            (> adjacent-bombs 0)
            adjacent-bombs
            :else
            :uncovered))))

(fn love.draw []
   (love.graphics.setFont font)

   (each [x y cell (icells)]
      (let [cell (. grid y x)]
         (var tile (draw-tile-for-cell x y cell))

         ;; draw all bombs when game is over
         (when (and (game-over?) cell.bomb)
            (if (= cell.state :flag)
               (set tile :flagged-bomb)
               :else
               (set tile :bomb)))

         (draw-tile
            tile
            (* (- x 1) tile-draw-size)
            (* (- y 1) tile-draw-size))))

   (draw-status-bar))
