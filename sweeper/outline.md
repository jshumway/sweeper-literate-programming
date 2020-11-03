Sweeper Lit Programming Outline

Introduction to the essary
Introduction to the game
Modelling the game
	grid
	game state
	initialization
Drawing the grid
	loading the images
	icells grid iterator (hmm, move this up?)
	placing bombs (hmm)
	drawing state / love.update (selected coord)
	countdown mode introduction
	getting the right tile
	ineighbors iterator
	surrounding bombs
	getting the tile for a cell
	draw tile / draw grid
Gameplay
	Flood uncover algorithm
	Uncover cell
	Uncover initial cell
	Flood uncover flag
	Mark cell
	Count cells and predicate functions
	Game over
	Mousereleased callback
	Keypressed callback
Wrapping up
	get status line
	font
	draw status bar
	love.draw



Should I cut "regular mode" in favor of countdown mode being the only option? I think it makes the game more fun to play and interesting to build, instead of "just another minesweeper". Then I could move the explanation into the "game intro" and remove the flags. I think I'm going to do this.

I could probably cut the marking stuff too. I don't really need '?', and I don't think it even makes sense in countdown mode, does it?

---

How big of a problem is it that I have to explain the program "bottom up"? I feel like it is worth a shot to avoid taking on a ton more complexity for this post.