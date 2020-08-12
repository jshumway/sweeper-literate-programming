;; GAME PARAMS

(local grid-width 19)
(local grid-height 14)

(local bomb-count 40)

;; APP STATE

;; TODO simplify this
(local tile-import-size 40)
(local tile-draw-size 40)

(local image (love.graphics.newImage "tiles-2.png"))
(local tile-quads [])

;; GAME STATE

(local grid {})

(var selected-x 0)
(var selected-y 0)
(var game-over? false)
(var countdown-mode? false)


(local tile-names {
   :covered 1
   :covered-hover 2
   :uncovered 3
   :flower 4
   :flag 5
   :? 6
   :flag-countdown 7
})

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

      (and countdown-mode? (= :flag name))
      (set quad (tile-quad :flag-countdown))

      :else
      (set quad (tile-quad name)))

   (love.graphics.draw image quad x y))

;; TODO:
;; - COUNTDOWN MODE -> the "adjacent bomb count" numbers decrease for each
;;   adjacent flag (toggle with key `c`)
;;    -> issues: flood uncover needs to interact with the adjusted counts,
;;       which means it needs to run when a flag is placed
;;    -> would be nice if flags weren't on a blue background in this mode
;;       so that the "count" was clearly tied to the blue backgrounds
;; - Redo the drawing system
;; - Build an icell iterator (each [x y cell (icells)])
;; - Build an ineighbors (each [nx ny cell (ineighbors x y)])
;; - It'd be cool to have a "flagged bomb" icon to show at the end of the game
;;   so the player could see how they did

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

(fn each-neighbor [x y f]
   (for [dx -1 1]
      (for [dy -1 1]
         (when (not (and (= dx 0) (= dy 0)))
            (let [[nx ny] [(+ x dx) (+ y dy)]
                  cell (-?> grid (. ny) (. nx))]
               (if cell
                  (f cell nx ny)))))))

(fn surrounding-flowers [x y]
   (var count 0)
   (each-neighbor x y (fn [cell nx ny]
      (when (and countdown-mode? (= cell.state :flag))
         (set count (- count 1)))
      (when cell.flower
         (set count (+ count 1)))))
   count)

(fn flood-uncover [x y]
   (local stack [[x y]])
   (while (> (# stack) 0)
      (let [[x y] (table.remove stack)]
         (tset grid y x :state :uncovered)
         (when (= (surrounding-flowers x y) 0)
            (each-neighbor x y (fn [cell nx ny]
               (when (or (= cell.state :covered) (= cell.state :?))
                  (table.insert stack [nx ny]))))))))

;; When marking a flag in countdown-mode any adjacent spaces that have
;; their visible neighbor count reduced to zero should be flood unfilled.
(fn flood-uncover-flag [x y]
   (local stack [])

   (each-neighbor x y (fn [cell nx ny]
      (when (and (= cell.state :uncovered)
                 (= (surrounding-flowers nx ny) 0))
         (flood-uncover nx ny)))))

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

(fn draw-tile-for-cell [x y cell]
   (let [selected? (and (= x selected-x) (= y selected-y))
         clicking? (love.mouse.isDown 1)
         adjacent-flowers (surrounding-flowers x y)]

      (if

         ;; COVERED => mouse hover -> :covered-hover, else -> :covered
         (= cell.state :covered)
         (if selected? :covered-hover :else :covered)

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
   (for [y 1 grid-height]
      (for [x 1 grid-width]
         (let [cell (. grid y x)]
            (var tile (draw-tile-for-cell x y cell))

            ;; draw all flowers when game is over
            (when (and game-over? cell.flower)
               (set tile :flower))

            (draw-tile
               tile
               (* (- x 1) tile-draw-size)
               (* (- y 1) tile-draw-size))))))
