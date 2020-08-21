;; Fennel, like Lua, is simple enough that you can wrap your head around it and
;; dig in deep, and powerful enough that you can write elegant code that
;; expresses your intention clearly while providing a lot of depth to explore.

;; TODO explain the basic rules of minesweeper in terms of covered and
;; uncovered. That you're revealing the grid.

;; Major constraint is that, in Lua, symbols must be defined before they can be
;; used, it isn't enough that they're in the same file, or that the symbol has
;; been defined by the time the code using it is run. Thus this lp essay is
;; present in an "inductive" style, where we build up the pieces we need before
;; combining them to reach our goal. I try to provide the high level game
;; motivation to help you keep track of where we're headed and what we're build
;; up to.

;; For literate programming, we want to rearrange the program to introduce
;; concepts in the best order for the reader.

(local grid-width 19)
(local grid-height 14)

;; The grid will be a 2d array. Each cell will store if it has a bomb at the
;; current location, and if it has been revealed. Cells that have not been
;; revealed can be in the normal :covered state, marked with a :flag, or a :?.
;; All cells are initially placed without a bomb and covered.

(local grid {})

;; TODO: `.` lets you combine multiple accessors instead of nesting
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
;; TODO I might be able to clean this up
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

;; -------------------------------------------------------------
;; -- Above this line is first draft essay, below is no essay --
;; -------------------------------------------------------------

;; Now we're ready to get into the actual gameplay!

;; The main form of gameplay is clicking on a cell to reveal. However, in
;; minesweeper when you reveal a cell there is a chance that it'll cause many
;; surrounding neighbor cells to also reveal themselves.
;;
;; Specifically, if you reveal a cell and it has no adjacent bombs, then it is
;; trivial to know that all surrounding eight cells are safe to reveal as well.
;; So the game goes ahead and does this for you. This isn't just to save the
;; player the annoyence of revealing cells that they don't have to think about
;; to know are safe, it is also a nice effect that can drastically alter how the
;; board looks, which is a nice gameplay hook.
;;
;; We'll call this a "flood uncover". It is important to know that any uncover
;; action has the potential to be a flood uncover, so we need to run this
;; algorithm each time the player clicks a cell.
;;
;; The algorithm is a basic breadth first search starting with the coordinate
;; that the player clicked. If the surrounding count is 0, then each covered
;; neighbor is added to the queue and the process repeats. In this way the
;; uncover action "floods outwards" until it runs into a "border" where each
;; cell in the border has an adjacent bomb count greater than 0.
;;
;; One other caveat to note is that cells marked with a flag will never be
;; uncovered automatically. In non-countdown mode a flag next to an uncovered
;; cell would be an obvious player error, but in countdown mode where the 0
;; adjacent count means "no more unaccounted for bombs", revaling a flagged cell
;; could cause the player to lose the game! If you're wondering "wait, does that
;; mean we need to flood uncover when a cell is marked with a flag too?", Yes!
;; We'll get there soon.

(fn flood-uncover [x y]
   (local stack [[x y]])
   (while (> (length stack) 0)
      (let [[x y] (table.remove stack)]
         (set-grid x y :state :uncovered)
         (when (= (surrounding-bombs x y) 0)
            (each [nx ny cell (ineighbors x y)]
               (when (or (= cell.state :covered) (= cell.state :?))
                  (table.insert stack [nx ny])))))))

;; With flood-uncover in hand, we can implement the full uncover-cell action
;; that we'll bind to left-click. We won't uncover a flag cell to prevent
;; misclicks from causing the player to lose.
;;
;; The only thing here is that, if the player clicked a bomb cell, we don't do
;; the flood unfill. The only impact here is how the grid looks when it is
;; frozen on the lose screen: only the bomb will be revealed, not any adjacent
;; empty cells.

(fn uncover-cell! []
   (let [cell (selected-cell)]
      (if (~= cell.state :flag)
         (if cell.bomb
            (set cell.state :uncovered)
            :else
            (flood-uncover selected-x selected-y)))))

;; If you recall from earlier, the initial left click is a special case: there
;; are no bombs, we need to place them _after_ the initial cell is uncovered.
;; Here is a modification of the above for this case: move the game from :init
;; state to :play state, place the random bombs, then flood uncover the
;; initially selected cell.

(fn uncover-initial-cell! []
   (set game-state :play)
   (place-bombs! selected-x selected-y)
   (flood-uncover selected-x selected-y))

;; Above I alluded to the fact that, when a cell has no adjacent bombs, all of
;; its neighbors are trivially safe to reveal without any interesting thought on
;; the part of the player required. Uncovering a cell can reveal a that it has
;; no adjacent bombs, and thus trigger a flood uncover.
;;
;; However, in countdown mode, _placing a flag_ causes all neighboring cells to
;; have their adjacent bomb count decrease by 1, potentially to zero! Thus it
;; creates a state where we might need to flood uncover more cells! In this way
;; placing a flag in countdown-mode is actually a risky action, just like
;; uncovering a cell is. If you flag the wrong cell, you might cause the flood
;; unfill to reveal a bomb! This is why I've highlighted flags yellow in
;; countdown mode.
;;
;; The algorithm to make this happen is simple: when the player flags a cells,
;; look at each neighbor of the new flag, as this is the set of cells whose
;; adjacent bomb count will have changed. For each of them with a new adjacent
;; bomb count of zero, initiate a flood-uncover starting at that cell.

(fn flood-uncover-flag [x y]
   "Marking a flag in countdown mode causes adjacent spaces that now show
    a count of 0 to have their neighbors revealed. This could cause the
    a bomb to be revealed and the player to lose the game if a flag location
    is placed incorrectly."
   (each [nx ny cell (ineighbors x y)]
      (when (and (= cell.state :uncovered)
                 (= (surrounding-bombs nx ny) 0))
         (flood-uncover nx ny))))

;; Now we can talk about the final action we'll be binding to mouse clicks:
;; marking cells. There are three ways a cell can be marked: :covered (unmarked),
;; :flag, and :?. Right clicking on a cell cycles through these three states.
;; This map encodes those transitions: if you're :covered, move to :flag. If
;; you're :flag, move to :?, and so on.

(local covered-cell-transitions {
   :covered :flag
   :flag :?
   :? :covered
})

;; And the action itself. Get the next mark state and transition the cell in
;; question to it. And, if we're in countdown mode and just marked a cell as a
;; flag, run the flood-uncover-flag routine from above.

(fn mark-cell! []
   (let [cell (selected-cell)
         next (. covered-cell-transitions cell.state)]
      (set-grid selected-x selected-y :state next)
      (when (and countdown-mode? (= next :flag))
         (flood-uncover-flag selected-x selected-y))))

;; With those three actions implemented, there is only one more thing we need to
;; handle mouse interactions: detecting if the game is over. If the player has
;; revealed a bomb, the game is lost. If the player has revealed each covered
;; cell without a bomb, they have won.


;; TODO: umm, how much do I really need to explain this? Probably just the
;; predicate function part.
;; ----------
;; count-cells is a helper function that takes a predicate and applies it to
;; each cell in the grid. If the predicate returns true, the overall count is
;; increased by 1.
;; ----------
;; To help determine if either of these conditions has been met we'll build a
;; few helper functions. This one takes a predicate function that, when given
;; a cell from the grid, returns true or false. The predicate function is called
;; on each cell in the grid, and each time true is returned a conuter is
;; incremented.
(fn count-cells [pred]
   (var c 0)
   (each [_ _ cell (icells)]
      (if (pred cell) (set c (+ c 1))))
   c)

;; Could also be defined as: #(and $.bomb (= $.state :uncovered))
(fn uncovered-bomb? [cell]
   (and cell.bomb (= cell.state :uncovered)))

;; Could also be defined as: #(and (not $.bomb) (= $.state :covered))
(fn covered-empty-cell? [cell]
   (and (not cell.bomb) (= cell.state :covered)))

;; game-over? simply combines the above helpers: if there are any uncovered
;; bombs the player has lost. If there are no more covered empty cells, they've
;; won.
;;
;; Of note: this function returns multiple values. If the game is over it
;; returns both `true` and the next state for the game to move to, `:lost`.
;; The Fennel special form `values` lets us return multiple values in this way.

(fn game-over? []
   "Returns (true, next-game-state) if the game is over, otherwise false."
   (if (> (count-cells uncovered-bomb?) 0)
      (values true :lost)

      (= (count-cells covered-empty-cell?) 0)
      (values true :won)

      :else
      false))

;; And now, finally, we can combine all of the above to handle the majority of
;; player interaction with the game. The interactions are broken down by game
;; state.
;;
;; Finally, after any uncovering has been executed, we check if the game is
;; over and update the state if it is. Notice how the `let` syntax for
;; destructuring multiple return values is a little different, but also
;; familiar.

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

   (let [(over? next-state) (game-over?)]
      (when over? (set game-state next-state))))

;; The last way the player can interact with the game is by pressing certain
;; keys. :escape quits the game, :r restarts it, and :c toggles countdown mode.
;; Restarting the game is as simple as re-running `init-game!`, which both
;; clears the grid and moves the game-state back to :init.

(fn love.keypressed [key]
   (match key
      ;; quit the game
      :escape
      (love.event.quit)

      ;; reset the game
      :r
      (init-game!)

      ;; toggle countdown mode
      :c
      (set countdown-mode? (not countdown-mode?))))

;; To round out the game, we'll build a status line to give the player some
;; feedback. The contents of the status line will depend on the game's state.
;;
;; :play and :lost are the interesting one. :play shows if the game is in
;; countdown or normal mode, and the number of flags placed compared to the
;; total number of bombs. The latter is always fixed, but the former needs to
;; be calculated. We use the same helper developed above for checking win and
;; loss conditions. This time we use the Fennel feature `hashfn`s, a convenient
;; shorthand function definition syntax useful for exactly these kinds of small
;; predicate functions.
;;
;; Similarly, in the :lost state we want to tell the player how many bombs were
;; left unflagged.

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

;; We load a font to render the status bar text with...

(local font (love.graphics.newFont "lilliput-steps.ttf" 28))

;; A simple routine to draw the status bar in the right place...

(fn draw-status-bar []
   (love.graphics.setFont font)
   (love.graphics.print (get-status-line) 6 557))

;; And we draw the two major display elements, the grid and the status bar.

(fn love.draw []
   (draw-grid)
   (draw-status-bar))
