;; For literate programming, we want to rearrange the program to introduce
;; concepts in the best order for the reader.

(local grid-width 19)
(local grid-height 14)

;; The grid will be a 2d array. Each cell will store if it has a bomb at the
;; current location, and if it has been revealed. Cells that have not been
;; revealed can be in the normal :covered state, marked with a :flag, or a :?.
;; All cells are initially placed without a bomb and covered.

(local grid {})

;; Bombs won't be placed until after the player has first clicked on a space,
;; to ensure the player cannot lose on their first turn.
(fn reset-grid! []
   (for [y 1 grid-height]
      (tset grid y {})
      (for [x 1 grid-width]
         (tset grid y x {:bomb false :state :covered}))))

;; The game can be in one of four states:
;;  * :init - the grid is blank and unrevealed, bombs have not yet been placed
;;  * :play - at least one cell has been revealed, bombs have been placed, and
;;            the player has neither won nor lost yet
;;  * :lost - a bomb tile was revealed so the player has lost
;;  * :won  - all non-bomb tiles have been uncovered so the player has won
(var game-state :init)

;; A helper function to determine if the game is in a terminal state.
(fn game-over? []
   (or (= game-state :won) (= game-state :lost)))

;; This brings us to the end of the logical side of initialization.  When
;; starting up or restarting the game we reset the state and reset the grid to
;; entirely blank.
(fn init-game! []
   (set game-state :init)
   (reset-grid!))

;; However there is more to be done to load the game. We need to load our small
;; image atlas and setup some graphics state to easily draw the different images.

;; First we load the image itself.
(local image (love.graphics.newImage "tiles.png"))

;; The image was created in a pixel editor with each tile a 10x10 square,
;; then exported at 400% resolution. Thus each tile is 40x40.
(local tile-size 40)

;; Love2d (and many other graphics systems) have tho concept of a quad, which
;; is a rectangular region in an image that can be quickly drawn. We'll create
;; a quad for all 16 images in tiles.png.
(local tile-quads [])

;; Unpack the image into quads. We know there are 2 rows of 8 columns. We want
;; to ensure that we insert the entire first row into `tile-quads` first,
;; followed by the entire second row, so the iteration is row-major.
(fn load-images! []
   (for [row 0 1]
      (for [col 0 7]
         (let [[x y] [(* col tile-size) (* row tile-size)]
               quad (love.graphics.newQuad x y tile-size tile-size (image:getDimensions))]
            (table.insert tile-quads quad)))))

;; This map gives symbol names to the quads that we've extracted. The 8 tiles
;; in the top row of the image have meaningful names, the second row is just
;; the numbers 1 to 8, which can be specified as numbers instead of symbols.
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

;; Now we can load the game in its initial state!

(fn love.load []
   (load-images!)
   (init-game!))

;; Before moving on to bomb placements, we're going to build a helpful utility
;; function that allows us to easily iterate through every cell in the grid.
;; We'd like to take code like this:
;;
;; (for [y row (ipairs grid)]
;;    (for [x cell (ipairs row)]
;;       ... do something with x, y, and cell...))
;;
;; And instead be able to write:
;;
;; (for [x y cell (icells)]
;;    ... do something with x, y, and cell...)
;;
;; Not only is it cleaner, but it is decoupled from the implementation details
;; of grid. Now the user of `icells` doesn't need to know that grid is a column-
;; major 2d array.
;;
;; In another language like Java we'd need to "unpack" the iteration, maintaining
;; the state needed to "resume" iteration each time the iterator is asked for
;; the next element. Luckily Lua provides coroutines, allowing us to write code
;; just like above, just needing some extra book keeping. See the appendix for
;; a non-coroutine alternative version.

;; TODO honestly just link to and quote the docs:
;; "Actually, coroutines provide a powerful tool for this task. Again, the key
;; feature is their ability to turn upside-down the relationship between caller
;; and callee. With this feature, we can write iterators without worrying about
;; how to keep state between successive calls to the iterator."
;; https://www.lua.org/pil/9.3.html

(fn icells []
   "Iterates over all the points in the grid as (x, y, cell)."
   (coroutine.wrap (fn []
      (each [y row (ipairs grid)]
         (each [x cell (ipairs row)]
            (coroutine.yield x y cell))))))

;; Bombs will be placed when the player selects the first cell to reveal. This
;; ensures that the first selected cell will never contain a bomb, and that all
;; bombs will be placed with equal random chance.

(local bomb-count 40)

;; Given the location of the player's first selection, we place bombs randomly
;; by first constructing a list of all possible locations, excluding the initial
;; selection. Then we remove random elements from the list and place bombs at
;; those locations.

(fn place-bombs! [player-x player-y]
   "Fill the grid with hidden bombs while avoiding the space [player-x player-y]"

   (var possible-locations [])
   (each [x y _ (icells)]
      (when (or (~= x player-x) (~= y player-y))
         (table.insert possible-locations [x y])))

   (for [i 1 bomb-count]
      (let [ndx (love.math.random (length possible-locations))
            [x y] (table.remove possible-locations ndx)]
         (tset grid y x :bomb true))))

;; Next we want to track where the player's mouse is pointing in terms of
;; cells in the grid. We create state to track the x and y coordinate of the
;; cell and update them each frame in love.update. All other updates are tied
;; to keypresses and mouseclicks, which will be handled in their respective
;; callbacks later.

(var selected-x 0)
(var selected-y 0)

(fn love.update []
   (let [(x y) (love.mouse.getPosition)]
      (set selected-x
         (math.min grid-width (math.floor (+ 1 (/ x tile-size)))))
      (set selected-y
         (math.min grid-height (math.floor (+ 1 (/ y tile-size)))))))

;; Before we get to drawing the board we need one more piece of game state.
;; Countdown Mode is an alternative display mode. You can think if it this way:
;; instead of displaying in uncovered cells the number of adjacent bombs, you
;; display the number of adjacent bombs that have not yet been flagged. The
;; thinking goes that, if the player has accounted for an adjacent bomb by
;; flagging it then the adjacency counts can ignore it.
;;
;; In addition to changing the drawing logic, countdown mode also changes how
;; placing flags works, but we'll discuss that when we get there.
;;
;; By default, we'll start in countdown mode, becaues it is the one I happen
;; to prefer :D

(var countdown-mode? true)





;; Which would I prefer to discuss first? Drawing the full board, or doing the
;; game logic updates?





;; MAYBE DRAWING THE BASIC GRID? THAT FEELS LIKE IT SHOULD COME LATER.


;; GAME PARAMS

;; APP STATE

(local font (love.graphics.newFont "lilliput-steps.ttf" 28))


;; GAME STATE

;; What relies on countdown-mode?
;; keypressed -> deciding what to do in countdown-mode?
;; drawing cells -> if there is a flag in countodwn mode
;; drawing cells -> adjacent count
;; counting surrounding bombs


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

(fn ineighbors [x y]
   "Iterates over all the valid neighbors of point (x, y) as (nx, ny, cell)."
   (coroutine.wrap (fn []
      (for [dx -1 1]
         (for [dy -1 1]
            (when (or (~= dx 0) (~= dy 0))
               (let [[nx ny] [(+ x dx) (+ y dy)]
                     cell (-?> grid (. ny) (. nx))]
                  (if cell (coroutine.yield nx ny cell)))))))))

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
         (set game-state :play)
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

(fn count-cells [pred]
   (var c 0)
   (each [_ _ cell (icells)]
      (if (pred cell) (set c (+ c 1))))
   c)

(fn get-status-line []
   (match game-state
      :init
      "LEFT CLICK ANY TILE TO BEGIN..."

      :play
      (let [mode (if countdown-mode? "[countdown]" :else "[normal]")
            flags (count-cells #(= $.state :flag))]
         (.. mode " " flags " FLAGS / " bomb-count " BOMBS"))

      :lost
      (let [unflagged-bombs (count-cells #(and $.bomb (~= $.state :flag)))]
         (.. "DEFEAT! " unflagged-bombs " BOMBS EXPLODE. [R]ESTART"))

      :won
      "VICTORY! ALL BOMBS DISARMED! [R]ESTART"))

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

;; it might be worth breaking these back up into independent draw routines
;; so they can be explained in their proper sections, instead of way here at
;; the end.
;;
;; the LP thing is definitely causing things to get grouped together
;; conceptually, which is interesting.
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
            (* (- x 1) tile-size)
            (* (- y 1) tile-size))))

   ;; Draw the status line
   (love.graphics.print (get-status-line) 6 557))
