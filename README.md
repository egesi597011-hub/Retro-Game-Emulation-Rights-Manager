# 🕹️ Retro Game Emulation Rights Manager

A Clarity smart contract that revolutionizes retro gaming by providing a decentralized licensing system for classic games, ensuring fair compensation for developers and publishers while enabling legitimate emulation.

## ✨ Features

- 🎮 **Game Registration**: Developers can register their retro games with metadata and licensing terms
- 💳 **Flexible Licensing**: Support for unlimited, monthly, and custom licensing models
- 🎯 **Play Tracking**: Monitor game sessions and usage statistics
- 💰 **Automated Royalties**: Transparent revenue distribution to developers and publishers
- 🔐 **Access Control**: Secure license validation and session management
- 📊 **Analytics**: Comprehensive play statistics and earnings tracking

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet)
- Stacks wallet with STX tokens

### Installation

1. Clone this repository
2. Navigate to the project directory
3. Run `clarinet check` to verify the contract

## 📖 Contract Usage

### For Game Developers

#### Register a New Game
```clarity
(contract-call? .retro-game-rights register-game 
  "Pac-Man" 
  'SP1DEVELOPER 
  u1980 
  u1000000 
  u7000 
  (some "https://metadata.com/pacman.json"))
```

#### Update Game Settings
```clarity
(contract-call? .retro-game-rights update-play-cost u1 u2000000)
(contract-call? .retro-game-rights update-game-status u1 true)
```

#### Withdraw Earnings
```clarity
(contract-call? .retro-game-rights withdraw-developer-earnings)
```

### For Players

#### Purchase a License
```clarity
(contract-call? .retro-game-rights purchase-license 
  u1 
  "monthly" 
  u4320 
  u100)
```

#### Play a Game
```clarity
(contract-call? .retro-game-rights play-game u1)
```

#### End Play Session
```clarity
(contract-call? .retro-game-rights end-play-session u1 u3600)
```

### For Publishers

#### Withdraw Publisher Earnings
```clarity
(contract-call? .retro-game-rights withdraw-publisher-earnings)
```

## 🔍 Read-Only Functions

### Get Game Information
```clarity
(contract-call? .retro-game-rights get-game u1)
```

### Check License Status
```clarity
(contract-call? .retro-game-rights get-license 'SP1PLAYER u1)
```

### View Earnings
```clarity
(contract-call? .retro-game-rights get-developer-earnings 'SP1DEVELOPER)
(contract-call? .retro-game-rights get-publisher-earnings 'SP1PUBLISHER)
```

### Platform Statistics
```clarity
(contract-call? .retro-game-rights get-total-games)
(contract-call? .retro-game-rights get-platform-fee-rate)
```

## 💡 Key Concepts

### License Types
- **unlimited**: Full access for specified number of plays
- **monthly**: Discounted rate for time-based access
- **custom**: Developer-defined licensing terms

### Revenue Distribution
- Platform fee: 2.5% (adjustable by contract owner)
- Developer share: Based on royalty rate set during registration
- Publisher share: Remaining amount after platform fee and developer share

### Access Control
- Only developers can update their games
- Only contract owner can modify platform settings
- License validation ensures fair usage

## 🛠️ Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u100 | ERR_NOT_AUTHORIZED | Unauthorized access attempt |
| u101 | ERR_GAME_NOT_FOUND | Game does not exist |
| u102 | ERR_INSUFFICIENT_PAYMENT | Insufficient STX for transaction |
| u103 | ERR_INVALID_ROYALTY_RATE | Royalty rate outside valid range |
| u104 | ERR_GAME_ALREADY_EXISTS | Game ID already registered |
| u105 | ERR_INVALID_LICENSE_TYPE | Unsupported license type |
| u106 | ERR_LICENSE_EXPIRED | License has expired |
| u107 | ERR_INSUFFICIENT_BALANCE | Insufficient license plays remaining |

## 🎯 Use Cases

### Arcade Operators
- Purchase monthly licenses for multiple games
- Track usage statistics for business insights
- Automated royalty payments to rights holders

### Individual Gamers  
- Buy per-play access to favorite retro games
- Support original developers through play fees
- Access authenticated classic gaming experiences

### Game Preservationists
- Ensure legal compliance for game preservation
- Provide sustainable funding model for retro gaming
- Maintain transparent licensing records on blockchain

## 🔒 Security Features

- Immutable game registration records
- Cryptographic license validation
- Transparent revenue distribution
- Time-based access control
- Session tracking and analytics

## 🌟 Benefits

### For Developers
- 💰 Passive income from classic games
- 📈 Analytics on game popularity
- 🔄 Flexible licensing models
- 🎯 Direct fan engagement

### For Players  
- ✅ Legal access to retro games
- 🎮 Authentic gaming experiences
- 💝 Support original creators
- 📱 Modern licensing convenience

### For the Industry
- 🏛️ Preserve gaming history
- ⚖️ Establish legal precedents
- 🌱 Sustainable retro gaming ecosystem
- 🔗 Bridge classic and modern gaming

## 📊 Contract Statistics

The contract tracks comprehensive metrics including:
- Total games registered
- Play sessions and duration
- Revenue distribution
- License utilization rates
- Developer and publisher earnings

## 🤝 Contributing

This contract serves as a foundation for retro gaming rights management. Contributions and improvements are welcome to enhance the gaming preservation ecosystem.

## 📄 License

This contract is designed to manage licensing rights for retro games while respecting intellectual property and promoting fair compensation for creators.

---

*Built with ❤️ for the retro gaming community*
