;; For literate programming, we want to rearrange the program to introduce
;; concepts in the best order for the reader.

(local grid-width 19)
(local grid-height 14)

;; The grid will be a 2d array. Each cell will store if it has a bomb at the
;; current location, and if it has been revealed. Cells that have not been
;; revealed can be in the normal :covered state, marked with a :flag, or a :?.
;; All cells are initially placed without a bomb and covered.

(local grid {})

;; TODO: (. ...) lets you combine multiple accessors instead of nesting
(fn get-grid [x y]
   (. grid y x))

;; TODO: maybe this is more trouble than it is worth, but I think a few
;; examples is all that is needed, and the point that the number of arguments
;; to `tset` must be known at compile time, not when the function is called at
;; runtime or it won't work.
(macro set-grid [x y ...]
   `(tset grid ,y ,x ,...))

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
(local tile-for-name {
   :covered 1
   :covered-hover 2
   :empty 3
   :bomb 4
   :flag 5
   :? 6
   :flag-countdown 7
   :flagged-bomb 8
})

;; And quad-for-tile allows us to use symbolic tile names throughout the code
;; (:covered, :flag, 3, :empty) and easily lookup the quad needed to draw the
;; corrisponding image.
(fn quad-for-tile [s]
   (. tile-quads
      (if (= (type s) :number) (+ s 8)
         :else (. tile-for-name s))))

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
         (set-grid x y :bomb true))))

;; Next we want to track where the player's mouse is pointing in terms of
;; cells in the grid. We create state to track the x and y coordinate of the
;; cell and update them each frame in love.update. All other updates are tied
;; to keypresses and mouseclicks, which will be handled in their respective
;; callbacks later.

(var selected-x 0)
(var selected-y 0)

;; A small helper to get the cell that the mouse is hovering over.
(fn selected-cell []
   (get-grid selected-x selected-y))

;; Note that this means we will always have a cell selected because the actual
;; mouse location is bound to the grid. This is nice because we never need to
;; worry about the mouse clicking anywhere besides the grid, or not having a
;; cell selected.
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

;; The first step in drawing is deciding, for each cell in the grid, which tile
;; to use to represent it. Each cell can be in one of four states:
;;
;;    :covered -> a blank, covered tile
;;    :flags -> a covered tile that has been marked with a flag
;;    :? -> a covered tile that has been marked with a question mark
;;    :uncovered -> a tile the player has clicked to reveal what is beneath it

;; Drawing a covered cell is simple. The only interesting behavior is that we
;; draw a different tile while the game is in progress if the mouse is hovering
;; over the cell, to create a sense of interactivity.
(fn tile-for-covered-cell [hovering?]
   (if (and hovering? (not (game-over?))) :covered-hover
      :else :covered))

;; For the flag there are two decisions to make. If the player has flagged a
;; cell they are stating a belief that there is a bomb at that location.
;; Therefore the game will not let the player click the cell to reveal it, as
;; they would lose the game. However, we want to create a sense of interactivity
;; —the feeling that the mouse click has been registered—so we change the cell
;; to a normal :covered tile while the is being clicked.
;;
;; In addition, when the game is in countdown mode flags are special, as they
;; decrease the adjacent counts. To emphasise that the flags are important in
;; this mode, a different tile is drawn for them.

(fn tile-for-flagged-cell [clicking?]
   (if (and clicking? (not (game-over?))) :covered
      countdown-mode? :flag-countdown
      :else :flag))

;; Similar to flags, the player isn't allowed to directly reveal a :? cell. To
;; preserve a sense of interactivity render a clicked on :? as :covered. Like
;; with flags, when the game is over, we don't want to create the impression
;; that cells can be clicked so they don't react to clicking.
(fn tile-for-question-cell [clicking?]
   (if (and clicking? (not (game-over?))) :covered
      :else :?))

;; Deciding what tile to draw for uncovered cells is more difficult as it
;; depends on the number of adjacent bombs. If there are no adjacent bombs
;; then the :empty tile will be drawn. Otherwise a tile with the appropriate
;; number should be drawn.
;;
;; Later when we get to updating the game state there will be other pieces of
;; code that need to do similar operations on the set of cells that are adjacent
;; to the given cell. Thus we'll create a new iterator, ineighbors, that
;; iterates through a cells neighbors!

;; The main complication of ineighbors is filtering out cells that aren't valid
;; because they're off the grid in one direction or another. The Fennel macro
;; `-?>` is a "thread maybe" macro that only prefroms each subsequent operation
;; if the result of the previous is non-nil.

(fn ineighbors [x y]
   "Iterates over all the valid neighbors of point (x, y) as (nx, ny, cell)."
   (coroutine.wrap (fn []
      (for [dx -1 1]
         (for [dy -1 1]
            (when (or (~= dx 0) (~= dy 0))
               (let [[nx ny] [(+ x dx) (+ y dy)]
                     cell (-?> grid (. ny) (. nx))]
                  (if cell (coroutine.yield nx ny cell)))))))))

;; We can use ineighbors to write a straightforward calculation of the number of
;; bombs adjacent to the given position. As mentioned above, in countdown mode
;; any adjacent flags detract from the adjacency count, effectively create a
;; count of "unaccounted for bombs".
;;
(fn surrounding-bombs [x y]
   (var count 0)
   (each [nx ny cell (ineighbors x y)]
      (when (and countdown-mode? (= cell.state :flag))
         (set count (- count 1)))
      (when cell.bomb
         (set count (+ count 1))))
   (math.max 0 count))

;; TODO: this "draw" wording is especially unappealing. Also, talk about
;; returning the number as the symbol for the quad that is the numeric
;; image. Or something.
;;
;; Now we have the tools we need to determine which tile to draw for an
;; uncovered cell. If the player has revealed a bomb, draw it. If there are
;; adjacent bombs draw the count. Otherwise draw an empty tile.

(fn tile-for-uncovered-cell [x y bomb?]
   (let [adjacent-bomb-count (surrounding-bombs x y)]
      (if bomb? :bomb
         (> adjacent-bomb-count 0) adjacent-bomb-count
         :else :empty)))

;; We can put it all together to get the tile needed to draw any cell.

(fn tile-for-cell [x y cell]
   ;; The state of the mouse influences what we draw, so record if the mouse is
   ;; hovering over the current cell and if the current cell is being clicked.
   (let [hovering? (and (= x selected-x) (= y selected-y))
         clicking? (and hovering? (love.mouse.isDown 1))]

      (match cell.state
         :covered (tile-for-covered-cell hovering?)
         :flag (tile-for-flagged-cell clicking?)
         :? (tile-for-question-cell clicking?)
         :uncovered (tile-for-uncovered-cell x y cell.bomb))))

(fn draw-tile [name px py]
   (love.graphics.draw image (quad-for-tile name) px py))

;; Now we can draw the full grid. Of note is the special logic that happens when
;; the game is over, where bombs are drawn instead of being hidden. In addition,
;; bombs that were correctly flagged have a unique tile so the player can see
;; which bombs they figured out and which they missed.

(fn draw-grid []
   (each [x y cell (icells)]

      ;; TODO it still feels like there is room to improve this

      ;; Find the default tile to draw for the cell
      (var tile (tile-for-cell x y cell))

      ;; If the game is over some cells should have bomb tiles draw insetad.
      (when (and (game-over?) cell.bomb)
         (if (= cell.state :flag)
            (set tile :flagged-bomb)
            :else
            (set tile :bomb)))

      (draw-tile
         tile
         (* (- x 1) tile-size)
         (* (- y 1) tile-size))))



;; --------------------------

(fn flood-uncover [x y]
   (local stack [[x y]])
   (while (> (# stack) 0)
      (let [[x y] (table.remove stack)]
         (set-grid x y :state :uncovered)
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


;; TODO consider splitting this up into two pieces, game-won? and game-lost?
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

(fn uncover-initial-cell! []
   (set game-state :play)
   (place-bombs! selected-x selected-y)
   (flood-uncover selected-x selected-y))

(fn uncover-cell! []
   (let [cell (selected-cell)]
      (if (~= cell.state :flag)
         (if cell.bomb
            (set cell.state :uncovered)
            :else
            (flood-uncover selected-x selected-y)))))

(local covered-cell-transitions {
   :covered :flag
   :flag :?
   :? :covered
})

(fn mark-cell! []
   (let [cell (selected-cell)
         next (. covered-cell-transitions cell.state)]
      (set-grid selected-x selected-y :state next)
      (when (and countdown-mode? (= next :flag))
         (flood-uncover-flag selected-x selected-y))))

(fn love.mousereleased [x y button]
   (match game-state
      :init
      (when (= button 1)
         (uncover-initial-cell!))

      :play
      (if (= button 1)
         (uncover-cell!)
         (= button 2)
         (mark-cell!)))

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

;; it might be worth breaking these back up into independent draw routines
;; so they can be explained in their proper sections, instead of way here at
;; the end.
;;
;; the LP thing is definitely causing things to get grouped together
;; conceptually, which is interesting.

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

(local font (love.graphics.newFont "lilliput-steps.ttf" 28))

(fn love.draw []
   (draw-grid)
   (love.graphics.setFont font)
   ;; Draw the status line
   (love.graphics.print (get-status-line) 6 557))
