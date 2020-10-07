(local suits [:clubs :diamonds :hearts :spades])

(local ranks [2 3 4 5 6 7 8 9 10 :jack :queen :king :ace])
;; better?
;; (local ranks [:2 :3 :4 :5 :6 :7 :8 :9 :10 :jack :queen :king :ace])

(fn rank-value [rank]
   (if (= :number (type rank))
      rank
      (= rank :ace)
      1
      :else
      10))

(fn sum-cards [cs]
   (var sum 0)
   (var has-ace false)
   (each [_ [rank _] (ipairs cs)]
      (set has-ace (or has-ace (= rank :ace)))
      (set sum (+ sum (rank-value rank))))
   (if (and has-ace (<= sum 11))
      (+ sum 10)
      :else
      sum))

(local deck {})
(local hand [])
(local dealer [])

;; :play, :end
(var round-state :play)

(fn init-deck! []
   (each [_ suit (ipairs suits)]
      (each [_ rank (ipairs ranks)]
         (table.insert deck [rank suit]))))

(fn draw-cards! [dest n]
   (for [i 1 n]
      (assert (> (length deck) 0) "No cards left in deck!")
      (table.insert dest (table.remove deck (love.math.random (length deck))))))

(fn love.load []
   (init-deck!)
   (draw-cards! hand 2)
   (draw-cards! dealer 2))

(fn love.keypressed [key]
   (match key
      (:h  ? (= round-state :play))
      (draw-cards! hand 1)

      (:s ? (= round-state :play))
      (set round-state :end)))

(fn get-winner []
   (let [player-msg "YOU, THE PLAYER!!! :D"
         dealer-msg "OH NO, THE DEALER! :( D: G:"
         draw-msg "LOOKS LIKE IT WAS A DRAW..."

         player-sum (sum-cards hand)
         dealer-sum (sum-cards dealer)
         player-bust (> player-sum 21)
         dealer-bust (> dealer-sum 21)]
      (if
         (and player-bust dealer-bust)
         draw-msg

         (and player-bust (not dealer-bust))
         dealer-msg

         (and (not player-bust) dealer-bust)
         player-msg

         (> player-sum dealer-sum)
         player-msg

         :else
         dealer-msg)))

(fn love.draw []
   (let [output {}
         append #(table.insert output $1)
         break #(append "\n")]

      (append "BLACKJACK")

      (break)

      (append "DEALER'S HAND")
      (each [_ [rank suit] (ipairs dealer)]
         (append (.. rank " of " suit)))
      (append (.. "TOTAL: " (sum-cards dealer)))

      (break)

      (append "PLAYER'S HAND")
      (each [_ [rank suit] (ipairs hand)]
         (append (.. rank " of " suit)))
      (append (.. "TOTAL: " (sum-cards hand)))

      (when (= round-state :end)
         (break)
         (break)
         (append "AND THE WINNER IS...")
         (break)
         (break)
         (append (get-winner)))

      (love.graphics.print (table.concat output "\n") 15 15)))


