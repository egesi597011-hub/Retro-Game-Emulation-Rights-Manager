(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_GAME_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u102))
(define-constant ERR_INVALID_ROYALTY_RATE (err u103))
(define-constant ERR_GAME_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_LICENSE_TYPE (err u105))
(define-constant ERR_LICENSE_EXPIRED (err u106))
(define-constant ERR_INSUFFICIENT_BALANCE (err u107))
(define-constant ERR_INVALID_PRICE_ADJUSTMENT (err u108))
(define-constant ERR_ALREADY_RATED (err u109))
(define-constant ERR_INVALID_RATING (err u110))
(define-constant ERR_MUST_PLAY_FIRST (err u111))
(define-constant MAX_PRICE_MULTIPLIER u300)
(define-constant MIN_PRICE_MULTIPLIER u50)
(define-constant DEMAND_THRESHOLD_HIGH u10)
(define-constant DEMAND_THRESHOLD_LOW u3)

(define-data-var contract-enabled bool true)
(define-data-var total-games uint u0)
(define-data-var platform-fee-rate uint u250)
(define-data-var pricing-window-blocks uint u1440)
(define-data-var platform-fee-balance uint u0)

(define-map games
  { game-id: uint }
  {
    title: (string-ascii 64),
    developer: principal,
    publisher: principal,
    release-year: uint,
    play-cost: uint,
    royalty-rate: uint,
    total-plays: uint,
    total-revenue: uint,
    is-active: bool,
    metadata-uri: (optional (string-ascii 256))
  }
)

(define-map game-licenses
  { licensee: principal, game-id: uint }
  {
    license-type: (string-ascii 16),
    expiry-block: uint,
    max-plays: uint,
    plays-used: uint,
    amount-paid: uint,
    issued-at: uint
  }
)

(define-map developer-earnings
  { developer: principal }
  { total-earned: uint, games-count: uint, withdrawn: uint }
)

(define-map publisher-earnings
  { publisher: principal }
  { total-earned: uint, games-count: uint, withdrawn: uint }
)

(define-map play-sessions
  { session-id: uint }
  {
    player: principal,
    game-id: uint,
    duration: uint,
    timestamp: uint,
    amount-paid: uint
  }
)

(define-data-var next-session-id uint u1)

(define-map game-demand-metrics
  { game-id: uint }
  {
    plays-last-window: uint,
    window-start-block: uint,
    peak-concurrent-sessions: uint,
    total-unique-players: uint,
    average-session-duration: uint,
    current-price-multiplier: uint
  }
)

(define-map game-price-history
  { game-id: uint, block-height: uint }
  {
    price: uint,
    multiplier: uint,
    plays-count: uint,
    reason: (string-ascii 32)
  }
)

(define-map player-game-stats
  { player: principal, game-id: uint }
  {
    total-plays: uint,
    last-played: uint,
    total-spent: uint,
    average-session-duration: uint
  }
)

(define-map game-ratings
  { game-id: uint }
  {
    total-ratings: uint,
    sum-ratings: uint,
    five-star-count: uint,
    four-star-count: uint,
    three-star-count: uint,
    two-star-count: uint,
    one-star-count: uint
  }
)

(define-map player-reviews
  { player: principal, game-id: uint }
  {
    rating: uint,
    review-text: (string-ascii 256),
    submitted-at: uint,
    helpful-votes: uint
  }
)

(define-map review-votes
  { voter: principal, reviewer: principal, game-id: uint }
  { voted: bool }
)

(define-public (register-game 
  (title (string-ascii 64))
  (publisher principal)
  (release-year uint)
  (play-cost uint)
  (royalty-rate uint)
  (metadata-uri (optional (string-ascii 256))))
  (let ((game-id (+ (var-get total-games) u1)))
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= royalty-rate u0) (<= royalty-rate u9000)) ERR_INVALID_ROYALTY_RATE)
    (asserts! (is-none (map-get? games { game-id: game-id })) ERR_GAME_ALREADY_EXISTS)
    
    (map-set games
      { game-id: game-id }
      {
        title: title,
        developer: tx-sender,
        publisher: publisher,
        release-year: release-year,
        play-cost: play-cost,
        royalty-rate: royalty-rate,
        total-plays: u0,
        total-revenue: u0,
        is-active: true,
        metadata-uri: metadata-uri
      })
    
    (map-set developer-earnings
      { developer: tx-sender }
      (merge 
        (default-to { total-earned: u0, games-count: u0, withdrawn: u0 }
          (map-get? developer-earnings { developer: tx-sender }))
        { games-count: (+ (get games-count 
          (default-to { total-earned: u0, games-count: u0, withdrawn: u0 }
            (map-get? developer-earnings { developer: tx-sender }))) u1) }))
    
    (map-set game-demand-metrics
      { game-id: game-id }
      {
        plays-last-window: u0,
        window-start-block: stacks-block-height,
        peak-concurrent-sessions: u0,
        total-unique-players: u0,
        average-session-duration: u0,
        current-price-multiplier: u100
      })
    
    (var-set total-games game-id)
    (ok game-id)))

(define-public (purchase-license 
  (game-id uint)
  (license-type (string-ascii 16))
  (duration-blocks uint)
  (max-plays uint))
  (let ((game (unwrap! (map-get? games { game-id: game-id }) ERR_GAME_NOT_FOUND))
        (license-cost (calculate-license-cost game-id license-type duration-blocks max-plays)))
    
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active game) ERR_GAME_NOT_FOUND)
    (asserts! (>= (stx-get-balance tx-sender) license-cost) ERR_INSUFFICIENT_PAYMENT)
    
    (try! (stx-transfer? license-cost tx-sender (as-contract tx-sender)))
    
    (map-set game-licenses
      { licensee: tx-sender, game-id: game-id }
      {
        license-type: license-type,
        expiry-block: (+ stacks-block-height duration-blocks),
        max-plays: max-plays,
        plays-used: u0,
        amount-paid: license-cost,
        issued-at: stacks-block-height
      })
    
    (unwrap-panic (distribute-license-revenue game license-cost))
    (ok true)))

(define-public (play-game (game-id uint))
  (let ((game (unwrap! (map-get? games { game-id: game-id }) ERR_GAME_NOT_FOUND))
        (license (map-get? game-licenses { licensee: tx-sender, game-id: game-id }))
        (base-cost (get play-cost game))
        (dynamic-cost (calculate-dynamic-price game-id))
        (play-cost (if (> dynamic-cost u0) dynamic-cost base-cost))
        (session-id (var-get next-session-id)))
    
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active game) ERR_GAME_NOT_FOUND)
    
    (if (is-some license)
      (begin
        (let ((license-data (unwrap-panic license)))
          (asserts! (< stacks-block-height (get expiry-block license-data)) ERR_LICENSE_EXPIRED)
          (asserts! (< (get plays-used license-data) (get max-plays license-data)) ERR_INSUFFICIENT_BALANCE)
          
          (map-set game-licenses
            { licensee: tx-sender, game-id: game-id }
            (merge license-data { plays-used: (+ (get plays-used license-data) u1) }))))
      (begin
        (asserts! (>= (stx-get-balance tx-sender) play-cost) ERR_INSUFFICIENT_PAYMENT)
        (try! (stx-transfer? play-cost tx-sender (as-contract tx-sender)))
        (unwrap-panic (distribute-play-revenue game play-cost))))
    
    (map-set games
      { game-id: game-id }
      (merge game { 
        total-plays: (+ (get total-plays game) u1),
        total-revenue: (+ (get total-revenue game) (if (is-some license) u0 play-cost))
      }))
    
    (map-set play-sessions
      { session-id: session-id }
      {
        player: tx-sender,
        game-id: game-id,
        duration: u0,
        timestamp: stacks-block-height,
        amount-paid: (if (is-some license) u0 play-cost)
      })
    
    (var-set next-session-id (+ session-id u1))
    (unwrap-panic (update-demand-metrics game-id tx-sender (if (is-some license) u0 play-cost)))
    (ok session-id)))

(define-public (end-play-session (session-id uint) (duration uint))
  (let ((session (unwrap! (map-get? play-sessions { session-id: session-id }) ERR_GAME_NOT_FOUND)))
    (asserts! (is-eq (get player session) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get duration session) u0) ERR_NOT_AUTHORIZED)
    
    (map-set play-sessions
      { session-id: session-id }
      (merge session { duration: duration }))
    (ok true)))

(define-public (withdraw-developer-earnings)
  (let ((earnings-data (unwrap! (map-get? developer-earnings { developer: tx-sender }) ERR_NOT_AUTHORIZED))
        (available (- (get total-earned earnings-data) (get withdrawn earnings-data))))
    (asserts! (> available u0) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? available tx-sender tx-sender)))
    (map-set developer-earnings
      { developer: tx-sender }
      (merge earnings-data { withdrawn: (get total-earned earnings-data) }))
    (ok available)))

(define-public (withdraw-publisher-earnings)
  (let ((earnings-data (unwrap! (map-get? publisher-earnings { publisher: tx-sender }) ERR_NOT_AUTHORIZED))
        (available (- (get total-earned earnings-data) (get withdrawn earnings-data))))
    (asserts! (> available u0) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? available tx-sender tx-sender)))
    (map-set publisher-earnings
      { publisher: tx-sender }
      (merge earnings-data { withdrawn: (get total-earned earnings-data) }))
    (ok available)))

(define-public (withdraw-platform-fees)
  (let ((amount (var-get platform-fee-balance)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (var-set platform-fee-balance u0)
    (ok amount)))

(define-public (update-game-status (game-id uint) (is-active bool))
  (let ((game (unwrap! (map-get? games { game-id: game-id }) ERR_GAME_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get developer game)) ERR_NOT_AUTHORIZED)
    
    (map-set games
      { game-id: game-id }
      (merge game { is-active: is-active }))
    (ok true)))

(define-public (update-play-cost (game-id uint) (new-cost uint))
  (let ((game (unwrap! (map-get? games { game-id: game-id }) ERR_GAME_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get developer game)) ERR_NOT_AUTHORIZED)
    
    (map-set games
      { game-id: game-id }
      (merge game { play-cost: new-cost }))
    (ok true)))

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_ROYALTY_RATE)
    (var-set platform-fee-rate new-rate)
    (ok true)))

(define-public (toggle-contract (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-enabled enabled)
    (ok true)))

(define-public (update-pricing-window (new-window-blocks uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= new-window-blocks u144) (<= new-window-blocks u14400)) ERR_INVALID_PRICE_ADJUSTMENT)
    (var-set pricing-window-blocks new-window-blocks)
    (ok true)))

(define-public (manual-price-adjustment (game-id uint) (multiplier uint) (reason (string-ascii 32)))
  (let ((game (unwrap! (map-get? games { game-id: game-id }) ERR_GAME_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get developer game)) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= multiplier MIN_PRICE_MULTIPLIER) (<= multiplier MAX_PRICE_MULTIPLIER)) ERR_INVALID_PRICE_ADJUSTMENT)
    
    (let ((metrics (default-to {
                     plays-last-window: u0,
                     window-start-block: stacks-block-height,
                     peak-concurrent-sessions: u0,
                     total-unique-players: u0,
                     average-session-duration: u0,
                     current-price-multiplier: u100
                   } (map-get? game-demand-metrics { game-id: game-id }))))
      
      (map-set game-demand-metrics
        { game-id: game-id }
        (merge metrics { current-price-multiplier: multiplier }))
      
      (map-set game-price-history
        { game-id: game-id, block-height: stacks-block-height }
        {
          price: (/ (* (get play-cost game) multiplier) u100),
          multiplier: multiplier,
          plays-count: (get total-plays game),
          reason: reason
        }))
    (ok true)))

(define-public (submit-review (game-id uint) (rating uint) (review-text (string-ascii 256)))
  (let ((game (unwrap! (map-get? games { game-id: game-id }) ERR_GAME_NOT_FOUND))
        (player-stats (map-get? player-game-stats { player: tx-sender, game-id: game-id }))
        (existing-review (map-get? player-reviews { player: tx-sender, game-id: game-id })))
    
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
    (asserts! (is-some player-stats) ERR_MUST_PLAY_FIRST)
    (asserts! (is-none existing-review) ERR_ALREADY_RATED)
    
    (let ((current-ratings (default-to {
                             total-ratings: u0,
                             sum-ratings: u0,
                             five-star-count: u0,
                             four-star-count: u0,
                             three-star-count: u0,
                             two-star-count: u0,
                             one-star-count: u0
                           } (map-get? game-ratings { game-id: game-id }))))
      
      (map-set game-ratings
        { game-id: game-id }
        {
          total-ratings: (+ (get total-ratings current-ratings) u1),
          sum-ratings: (+ (get sum-ratings current-ratings) rating),
          five-star-count: (if (is-eq rating u5) (+ (get five-star-count current-ratings) u1) (get five-star-count current-ratings)),
          four-star-count: (if (is-eq rating u4) (+ (get four-star-count current-ratings) u1) (get four-star-count current-ratings)),
          three-star-count: (if (is-eq rating u3) (+ (get three-star-count current-ratings) u1) (get three-star-count current-ratings)),
          two-star-count: (if (is-eq rating u2) (+ (get two-star-count current-ratings) u1) (get two-star-count current-ratings)),
          one-star-count: (if (is-eq rating u1) (+ (get one-star-count current-ratings) u1) (get one-star-count current-ratings))
        }))
    
    (map-set player-reviews
      { player: tx-sender, game-id: game-id }
      {
        rating: rating,
        review-text: review-text,
        submitted-at: stacks-block-height,
        helpful-votes: u0
      })
    (ok true)))

(define-public (vote-review-helpful (reviewer principal) (game-id uint))
  (let ((review (unwrap! (map-get? player-reviews { player: reviewer, game-id: game-id }) ERR_GAME_NOT_FOUND))
        (existing-vote (map-get? review-votes { voter: tx-sender, reviewer: reviewer, game-id: game-id })))
    
    (asserts! (var-get contract-enabled) ERR_NOT_AUTHORIZED)
    (asserts! (is-none existing-vote) ERR_ALREADY_RATED)
    (asserts! (not (is-eq tx-sender reviewer)) ERR_NOT_AUTHORIZED)
    
    (map-set player-reviews
      { player: reviewer, game-id: game-id }
      (merge review { helpful-votes: (+ (get helpful-votes review) u1) }))
    
    (map-set review-votes
      { voter: tx-sender, reviewer: reviewer, game-id: game-id }
      { voted: true })
    (ok true)))

(define-read-only (get-game (game-id uint))
  (map-get? games { game-id: game-id }))

(define-read-only (get-license (licensee principal) (game-id uint))
  (map-get? game-licenses { licensee: licensee, game-id: game-id }))

(define-read-only (get-developer-earnings (developer principal))
  (map-get? developer-earnings { developer: developer }))

(define-read-only (get-publisher-earnings (publisher principal))
  (map-get? publisher-earnings { publisher: publisher }))

(define-read-only (get-play-session (session-id uint))
  (map-get? play-sessions { session-id: session-id }))

(define-read-only (get-total-games)
  (var-get total-games))

(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate))

(define-read-only (get-platform-fee-balance)
  (var-get platform-fee-balance))

(define-read-only (is-contract-enabled)
  (var-get contract-enabled))

(define-read-only (get-game-demand-metrics (game-id uint))
  (map-get? game-demand-metrics { game-id: game-id }))

(define-read-only (get-game-price-history (game-id uint) (target-block uint))
  (map-get? game-price-history { game-id: game-id, block-height: target-block }))

(define-read-only (get-player-game-stats (player principal) (game-id uint))
  (map-get? player-game-stats { player: player, game-id: game-id }))

(define-read-only (get-current-game-price (game-id uint))
  (let ((game (map-get? games { game-id: game-id }))
        (metrics (map-get? game-demand-metrics { game-id: game-id })))
    (match game
      game-data
        (match metrics
          demand-data
            (let ((base-price (get play-cost game-data))
                  (multiplier (get current-price-multiplier demand-data)))
              (/ (* base-price multiplier) u100))
          (get play-cost game-data))
      u0)))

(define-read-only (get-pricing-window)
  (var-get pricing-window-blocks))

(define-read-only (get-game-popularity-score (game-id uint))
  (let ((metrics (map-get? game-demand-metrics { game-id: game-id })))
    (match metrics
      demand-data (+ (get plays-last-window demand-data) (get total-unique-players demand-data))
      u0)))

(define-read-only (get-game-ratings (game-id uint))
  (map-get? game-ratings { game-id: game-id }))

(define-read-only (get-player-review (player principal) (game-id uint))
  (map-get? player-reviews { player: player, game-id: game-id }))

(define-read-only (get-game-average-rating (game-id uint))
  (let ((ratings (map-get? game-ratings { game-id: game-id })))
    (match ratings
      rating-data
        (if (> (get total-ratings rating-data) u0)
          (/ (* (get sum-ratings rating-data) u100) (get total-ratings rating-data))
          u0)
      u0)))

(define-read-only (has-player-reviewed (player principal) (game-id uint))
  (is-some (map-get? player-reviews { player: player, game-id: game-id })))

(define-read-only (calculate-license-cost 
  (game-id uint)
  (license-type (string-ascii 16))
  (duration-blocks uint)
  (max-plays uint))
  (let ((game (unwrap! (map-get? games { game-id: game-id }) u0))
        (base-cost (get play-cost game)))
    (if (is-eq license-type "unlimited")
      (* base-cost max-plays)
      (if (is-eq license-type "monthly")
        (* base-cost (/ max-plays u2))
        (* base-cost max-plays)))))

(define-private (distribute-play-revenue (game { title: (string-ascii 64), developer: principal, publisher: principal, release-year: uint, play-cost: uint, royalty-rate: uint, total-plays: uint, total-revenue: uint, is-active: bool, metadata-uri: (optional (string-ascii 256)) }) (amount uint))
  (let ((platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
        (remaining (- amount platform-fee))
        (developer-share (/ (* remaining (get royalty-rate game)) u10000))
        (publisher-share (- remaining developer-share)))
    (var-set platform-fee-balance (+ (var-get platform-fee-balance) platform-fee))
    (map-set developer-earnings
      { developer: (get developer game) }
      (let ((current (default-to { total-earned: u0, games-count: u0, withdrawn: u0 }
                       (map-get? developer-earnings { developer: (get developer game) }))))
        (merge current { total-earned: (+ (get total-earned current) developer-share) })))
    (map-set publisher-earnings
      { publisher: (get publisher game) }
      (let ((current (default-to { total-earned: u0, games-count: u0, withdrawn: u0 }
                       (map-get? publisher-earnings { publisher: (get publisher game) }))))
        (merge current { total-earned: (+ (get total-earned current) publisher-share) })))
    (ok true)))

(define-private (distribute-license-revenue (game { title: (string-ascii 64), developer: principal, publisher: principal, release-year: uint, play-cost: uint, royalty-rate: uint, total-plays: uint, total-revenue: uint, is-active: bool, metadata-uri: (optional (string-ascii 256)) }) (amount uint))
  (let ((platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
        (remaining (- amount platform-fee))
        (developer-share (/ (* remaining (get royalty-rate game)) u10000))
        (publisher-share (- remaining developer-share)))
    (var-set platform-fee-balance (+ (var-get platform-fee-balance) platform-fee))
    (map-set developer-earnings
      { developer: (get developer game) }
      (let ((current (default-to { total-earned: u0, games-count: u0, withdrawn: u0 }
                       (map-get? developer-earnings { developer: (get developer game) }))))
        (merge current { total-earned: (+ (get total-earned current) developer-share) })))
    (map-set publisher-earnings
      { publisher: (get publisher game) }
      (let ((current (default-to { total-earned: u0, games-count: u0, withdrawn: u0 }
                       (map-get? publisher-earnings { publisher: (get publisher game) }))))
        (merge current { total-earned: (+ (get total-earned current) publisher-share) })))
    (ok true)))

(define-private (calculate-dynamic-price (game-id uint))
  (let ((game (map-get? games { game-id: game-id }))
        (metrics (map-get? game-demand-metrics { game-id: game-id })))
    (match game
      game-data
        (match metrics
          demand-data
            (let ((base-price (get play-cost game-data))
                  (multiplier (calculate-demand-multiplier game-id demand-data)))
              (/ (* base-price multiplier) u100))
          (get play-cost game-data))
      u0)))

(define-private (calculate-demand-multiplier (game-id uint) (metrics { plays-last-window: uint, window-start-block: uint, peak-concurrent-sessions: uint, total-unique-players: uint, average-session-duration: uint, current-price-multiplier: uint }))
  (let ((window-blocks (var-get pricing-window-blocks))
        (blocks-since-window-start (- stacks-block-height (get window-start-block metrics)))
        (plays-in-window (get plays-last-window metrics)))
    
    (if (>= blocks-since-window-start window-blocks)
      (begin
        (unwrap-panic (reset-demand-window game-id))
        u100)
      (if (>= plays-in-window DEMAND_THRESHOLD_HIGH)
        (let ((new-multiplier (+ (get current-price-multiplier metrics) u25)))
          (if (<= new-multiplier MAX_PRICE_MULTIPLIER) new-multiplier MAX_PRICE_MULTIPLIER))
        (if (<= plays-in-window DEMAND_THRESHOLD_LOW)
          (let ((new-multiplier (- (get current-price-multiplier metrics) u15)))
            (if (>= new-multiplier MIN_PRICE_MULTIPLIER) new-multiplier MIN_PRICE_MULTIPLIER))
          (get current-price-multiplier metrics))))))

(define-private (update-demand-metrics (game-id uint) (player principal) (amount-paid uint))
  (let ((current-metrics (default-to {
                           plays-last-window: u0,
                           window-start-block: stacks-block-height,
                           peak-concurrent-sessions: u0,
                           total-unique-players: u0,
                           average-session-duration: u0,
                           current-price-multiplier: u100
                         } (map-get? game-demand-metrics { game-id: game-id })))
        (player-stats (map-get? player-game-stats { player: player, game-id: game-id }))
        (is-new-player (is-none player-stats)))
    
    (let ((new-plays (+ (get plays-last-window current-metrics) u1))
          (new-multiplier (if (>= new-plays DEMAND_THRESHOLD_HIGH)
                            (let ((mult (+ (get current-price-multiplier current-metrics) u25)))
                              (if (<= mult MAX_PRICE_MULTIPLIER) mult MAX_PRICE_MULTIPLIER))
                            (if (<= new-plays DEMAND_THRESHOLD_LOW)
                              (let ((mult (- (get current-price-multiplier current-metrics) u15)))
                                (if (>= mult MIN_PRICE_MULTIPLIER) mult MIN_PRICE_MULTIPLIER))
                              (get current-price-multiplier current-metrics)))))
      (map-set game-demand-metrics
        { game-id: game-id }
        (merge current-metrics {
          plays-last-window: new-plays,
          total-unique-players: (if is-new-player
                                 (+ (get total-unique-players current-metrics) u1)
                                 (get total-unique-players current-metrics)),
          current-price-multiplier: new-multiplier
        })))
    
    (map-set player-game-stats
      { player: player, game-id: game-id }
      (let ((current-stats (default-to { total-plays: u0, last-played: u0, total-spent: u0, average-session-duration: u0 } player-stats)))
        (merge current-stats {
          total-plays: (+ (get total-plays current-stats) u1),
          last-played: stacks-block-height,
          total-spent: (+ (get total-spent current-stats) amount-paid)
        })))
    (ok true)))

(define-private (reset-demand-window (game-id uint))
  (let ((current-metrics (unwrap! (map-get? game-demand-metrics { game-id: game-id }) (ok false))))
    (map-set game-demand-metrics
      { game-id: game-id }
      (merge current-metrics {
        plays-last-window: u0,
        window-start-block: stacks-block-height
      }))
    (ok true)))
