(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_GAME_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u102))
(define-constant ERR_INVALID_ROYALTY_RATE (err u103))
(define-constant ERR_GAME_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_LICENSE_TYPE (err u105))
(define-constant ERR_LICENSE_EXPIRED (err u106))
(define-constant ERR_INSUFFICIENT_BALANCE (err u107))

(define-data-var contract-enabled bool true)
(define-data-var total-games uint u0)
(define-data-var platform-fee-rate uint u250)

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
        (play-cost (get play-cost game))
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

(define-read-only (is-contract-enabled)
  (var-get contract-enabled))

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
