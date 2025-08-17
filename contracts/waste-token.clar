;; EcoWaste Health Waste Token Contract
;; Clarity v2 (using latest syntax as of Stacks 2.1+)
;; Implements SIP-010 fungible token standard with additional staking for governance,
;; admin controls, allowances for approved transfers, and supply management.
;; Tokens incentivize proper medical waste handling and sustainable practices.

(define-trait fungible-token
  (
    ;; Transfer tokens with optional memo
    (transfer (principal uint principal (optional (buff 34))) (response bool uint))
    ;; Get balance of an account
    (get-balance (principal) (response uint uint))
    ;; Get total supply
    (get-total-supply () (response uint uint))
    ;; Get token name
    (get-name () (response (string-ascii 32) uint))
    ;; Get token symbol
    (get-symbol () (response (string-ascii 32) uint))
    ;; Get token decimals
    (get-decimals () (response uint uint))
    ;; Get token URI (optional metadata)
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-INSUFFICIENT-BALANCE u101)
(define-constant ERR-INSUFFICIENT-STAKE u102)
(define-constant ERR-MAX-SUPPLY-REACHED u103)
(define-constant ERR-PAUSED u104)
(define-constant ERR-ZERO-ADDRESS u105)
(define-constant ERR-INSUFFICIENT-ALLOWANCE u106)
(define-constant ERR-INVALID-AMOUNT u107)
(define-constant ERR-SELF-TRANSFER u108)

;; Token metadata
(define-constant TOKEN-NAME (as (string-ascii 32) "EcoWaste Token"))
(define-constant TOKEN-SYMBOL (as (string-ascii 32) "EWT"))
(define-constant TOKEN-DECIMALS u6)
(define-constant MAX-SUPPLY u1000000000000000) ;; 1B tokens with decimals
(define-constant TOKEN-URI (some u"https://ecowaste.health/token-metadata.json"))

;; Admin and contract state
(define-data-var admin principal tx-sender)
(define-data-var paused bool false)
(define-data-var total-supply uint u0)

;; Balances, stakes, and allowances
(define-map balances principal uint)
(define-map staked-balances principal uint)
(define-map allowances { owner: principal, spender: principal } uint)

;; Private helper: is-admin
(define-private (is-admin)
  (is-eq tx-sender (var-get admin))
)

;; Private helper: ensure not paused
(define-private (ensure-not-paused)
  (asserts! (not (var-get paused)) (err ERR-PAUSED))
)

;; Private helper: update allowance
(define-private (decrease-allowance (owner principal) (spender principal) (amount uint))
  (let ((current-allowance (default-to u0 (map-get? allowances { owner: owner, spender: spender }))))
    (if (>= current-allowance amount)
        (map-set allowances { owner: owner, spender: spender } (- current-allowance amount))
        (map-delete allowances { owner: owner, spender: spender })
    )
  )
)

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-admin tx-sender)) (err ERR-SELF-TRANSFER)) ;; Prevent self-assign
    (asserts! (not (is-eq new-admin 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (var-set admin new-admin)
    (print { event: "admin-transferred", new-admin: new-admin })
    (ok true)
  )
)

;; Pause/unpause the contract
(define-public (set-paused (pause bool))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (var-set paused pause)
    (print { event: "pause-status-changed", paused: pause })
    (ok pause)
  )
)

;; Mint new tokens (admin only)
(define-public (mint (recipient principal) (amount uint))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (let ((new-supply (+ (var-get total-supply) amount)))
      (asserts! (<= new-supply MAX-SUPPLY) (err ERR-MAX-SUPPLY-REACHED))
      (map-set balances recipient (+ amount (default-to u0 (map-get? balances recipient))))
      (var-set total-supply new-supply)
      (print { event: "mint", recipient: recipient, amount: amount })
      (ok true)
    )
  )
)

;; Burn tokens
(define-public (burn (amount uint))
  (begin
    (ensure-not-paused)
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (let ((balance (default-to u0 (map-get? balances tx-sender))))
      (asserts! (>= balance amount) (err ERR-INSUFFICIENT-BALANCE))
      (map-set balances tx-sender (- balance amount))
      (var-set total-supply (- (var-get total-supply) amount))
      (print { event: "burn", burner: tx-sender, amount: amount })
      (ok true)
    )
  )
)

;; SIP-010 transfer with optional memo
(define-public (transfer (recipient principal) (amount uint) (memo (optional (buff 34))))
  (begin
    (ensure-not-paused)
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (not (is-eq recipient tx-sender)) (err ERR-SELF-TRANSFER))
    (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (let ((sender-balance (default-to u0 (map-get? balances tx-sender))))
      (asserts! (>= sender-balance amount) (err ERR-INSUFFICIENT-BALANCE))
      (map-set balances tx-sender (- sender-balance amount))
      (map-set balances recipient (+ amount (default-to u0 (map-get? balances recipient))))
      (print { event: "transfer", sender: tx-sender, recipient: recipient, amount: amount, memo: memo })
      (ok true)
    )
  )
)

;; Approve spender allowance
(define-public (approve (spender principal) (amount uint))
  (begin
    (ensure-not-paused)
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (not (is-eq spender 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (map-set allowances { owner: tx-sender, spender: spender } amount)
    (print { event: "approve", owner: tx-sender, spender: spender, amount: amount })
    (ok true)
  )
)

;; Transfer from another account using allowance
(define-public (transfer-from (owner principal) (recipient principal) (amount uint))
  (begin
    (ensure-not-paused)
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (let (
      (allowance (default-to u0 (map-get? allowances { owner: owner, spender: tx-sender })))
      (owner-balance (default-to u0 (map-get? balances owner)))
    )
      (asserts! (>= allowance amount) (err ERR-INSUFFICIENT-ALLOWANCE))
      (asserts! (>= owner-balance amount) (err ERR-INSUFFICIENT-BALANCE))
      (decrease-allowance owner tx-sender amount)
      (map-set balances owner (- owner-balance amount))
      (map-set balances recipient (+ amount (default-to u0 (map-get? balances recipient))))
      (print { event: "transfer-from", owner: owner, spender: tx-sender, recipient: recipient, amount: amount })
      (ok true)
    )
  )
)

;; Stake tokens for governance
(define-public (stake (amount uint))
  (begin
    (ensure-not-paused)
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (let ((balance (default-to u0 (map-get? balances tx-sender))))
      (asserts! (>= balance amount) (err ERR-INSUFFICIENT-BALANCE))
      (map-set balances tx-sender (- balance amount))
      (map-set staked-balances tx-sender (+ amount (default-to u0 (map-get? staked-balances tx-sender))))
      (print { event: "stake", staker: tx-sender, amount: amount })
      (ok true)
    )
  )
)

;; Unstake tokens
(define-public (unstake (amount uint))
  (begin
    (ensure-not-paused)
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (let ((stake-balance (default-to u0 (map-get? staked-balances tx-sender))))
      (asserts! (>= stake-balance amount) (err ERR-INSUFFICIENT-STAKE))
      (map-set staked-balances tx-sender (- stake-balance amount))
      (map-set balances tx-sender (+ amount (default-to u0 (map-get? balances tx-sender))))
      (print { event: "unstake", unstaker: tx-sender, amount: amount })
      (ok true)
    )
  )
)

;; Read-only: get balance (SIP-010)
(define-read-only (get-balance (account principal))
  (ok (default-to u0 (map-get? balances account)))
)

;; Read-only: get staked balance
(define-read-only (get-staked-balance (account principal))
  (ok (default-to u0 (map-get? staked-balances account)))
)

;; Read-only: get effective balance (balance + staked)
(define-read-only (get-effective-balance (account principal))
  (ok (+ (default-to u0 (map-get? balances account)) (default-to u0 (map-get? staked-balances account))))
)

;; Read-only: get allowance
(define-read-only (get-allowance (owner principal) (spender principal))
  (ok (default-to u0 (map-get? allowances { owner: owner, spender: spender })))
)

;; Read-only: get total supply (SIP-010)
(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

;; Read-only: get name (SIP-010)
(define-read-only (get-name)
  (ok TOKEN-NAME)
)

;; Read-only: get symbol (SIP-010)
(define-read-only (get-symbol)
  (ok TOKEN-SYMBOL)
)

;; Read-only: get decimals (SIP-010)
(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS)
)

;; Read-only: get token URI (SIP-010)
(define-read-only (get-token-uri)
  (ok TOKEN-URI)
)

;; Read-only: get admin
(define-read-only (get-admin)
  (ok (var-get admin))
)

;; Read-only: check if paused
(define-read-only (is-paused)
  (ok (var-get paused))
)