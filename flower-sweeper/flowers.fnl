(local image (love.graphics.newImage "tiles-1.png"))
(local tile-import-size 40)
(local tile-draw-size 40)

(local tile-quads [])

(local tile-names {
   :covered 1
   :covered-hover 2
   :uncovered 3
   :flower 4
   :flag 5
   :? 6
})

(fn tile-for-number [n]
   (. tile-quads (+ n 8)))

(fn tile-quad [name]
   (. tile-quads (. tile-names name)))

(fn number? [arg]
   (= (type arg) :number))

;; TODO this is kind of gross
;; actually the whole flower drawing system is kinda gross
(fn draw-tile [name x y]
   (let [quad (if (number? name) (tile-for-number name) :else (tile-quad name))]
      (love.graphics.draw image quad x y)))

;; TODO:
;; - Have a grid that is adjacent bomb counts
;; - Initialize the bomb placements + adjacent bomb count grid when first tile
;;   is revealed
;; - Thus the initial state for a new game is a grid of all uncovered, no bomb
;;   cells, until the first click
;; - Redo the drawing system

(local grid-width 19)
(local grid-height 14)

(local grid {})

(var selected-x 0)
(var selected-y 0)
(var game-over? false)

(fn init-grid! []
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

   (for [i 1 40]
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
   (init-grid!)
   ;; TEMP test new images being drawn
   (tset grid 1 1 :state :flag)
   (tset grid 1 2 :state :?))

(fn draw-tiles-atlas []
   (let [padding 22]
      (each [i quad (ipairs tile-quads)]
         (love.graphics.draw image quad (* padding (- i 1)) 0))))

(fn love.keypressed [key]
   ;; quit the game
   (when (= key :escape)
      (love.event.quit))

   (when (= key :r)
      (init-grid!)))

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

(local covered-cell-transitions {
   :covered :flag
   :flag :?
   :? :covered
})

(fn love.mousereleased [x y button]
   (let [cell (. grid selected-y selected-x)]
      (when (= button 1)
         (when (~= cell.state :flag)
            (flood-uncover selected-x selected-y)))

      (when (= button 2)
         (let [next (. covered-cell-transitions cell.state)]
            (if next
               (tset grid selected-y selected-x :state next))))))


(fn love.update []
   (let [(x y) (love.mouse.getPosition)]
      (set selected-x (math.min grid-width
         (math.floor (+ 1 (/ x tile-draw-size)))))
      (set selected-y (math.min grid-height
         (math.floor (+ 1 (/ y tile-draw-size)))))))

(fn draw-tile-for-cell [x y cell]

   ;; RULES
   ;;
   ;; COVERED => mouse hover -> :covered-hover, else -> :covered
   ;; FLAG => mouse down -> :covered, else -> :flag
   ;; QUESTION => mouse down -> :uncovered, else -> :?
   ;; UNCOVERED => adjacent bombs? -> count, else -> :uncovered




   ;; TODO this doesn't actually work the way the tutorial says it should
   ;; work. when you click on a flag, it should show as covered, but it doesn't
   ;; becaues the tile will always be overwritten by the flag. so I need to
   ;; define the actual behavior needed. let's get back to that.
   (if (= cell.state :uncovered)
      :uncovered
      :else
      (if (and (= x selected-x) (= y selected-y))
         (if (love.mouse.isDown 1)
            (if (= cell.state :flag)
               :covered
               :else
               :uncovered)
            :else
            :covered-hover)
         :else
         :covered)))

(fn love.draw []
   (for [y 1 grid-height]
      (for [x 1 grid-width]
         (let [cell (. grid y x)]
            (var tile (draw-tile-for-cell x y cell))

            ;; TEMP draw all flowers
            (if (and cell.flower) ; game-over?
               (set tile :flower)
               (= cell.state :uncovered)
               (let [count (surrounding-flowers x y)]
                  (when (> count 0)
                     (set tile count))))

            (if (= cell.state :flag)
               (set tile :flag)
               (= cell.state :?)
               (set tile :?))

            (draw-tile tile
               (* (- x 1) tile-draw-size)
               (* (- y 1) tile-draw-size)))))

   ; (love.graphics.setColor 0 0 0)
   ; (love.graphics.print (.. "selected: (" selected-x ", " selected-y ")"))
   ; (love.graphics.setColor 1 1 1)
   )
