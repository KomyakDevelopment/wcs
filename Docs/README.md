# Untitled MMORPG Project

A permadeath MMORPG inspired by games like Deepwoken and Bloodlines, built with professional development practices and the WCS combat framework.

## Project Specifications

### Technical Standards
- **Language**: Luau
- **Architecture**: Object-Oriented Programming (OOP)
- **Combat Framework**: WCS (Wieldable Combat System) 2.4.0+
- **Performance**: Optimized for scalability and low latency
- **Code Structure**: Modular design with separation of concerns
- **State Management**: Dedicated state handlers for all game states
- **Module Loading**: Centralized module loaders for organized dependencies
- **Industry Standards**: Following Roblox and Luau best practices

### Development Tools
- **Version Control**: Git with Rojo 7.6.1
- **Package Manager**: Wally for dependency management
- **Toolchain Manager**: Rokit for tool versioning

## Core Game Features

### Permadeath System
- **Character Slots**: 1 default slot per player (expandable via Robux purchases)
- **Lives System**: 3 lives per character slot
- **Permanent Consequences**: Character death is meaningful and impactful

### Faction System
- **Four Factions**: Players choose between 4 distinct factions
- **Clan System**: Character identity tied to clan (replaces traditional "race" system)
- **Faction Mechanics**: TBD - Will be designed and implemented later

### Planned Features
- Combat system with skills, movesets, and status effects
- Character progression and customization
- Economy and monetization (character slots, cosmetics)
- World exploration and PvE content
- PvP combat zones
- Guild/party systems

## Project Structure

```
src/
├── server/
│   └── init.server.luau          # Server initialization & character management
├── client/
│   ├── init.client.luau          # Client initialization
│   └── inputHandler.client.luau  # Input handling for combat
└── shared/
    ├── movesets/                 # Combat movesets (character fighting styles)
    │   └── unarmed.luau
    ├── skills/                   # Individual combat abilities
    │   └── punch.luau
    └── statusEffects/            # Buffs, debuffs, and status conditions
        └── stun.luau
```

## Getting Started

### Prerequisites
- [Rojo](https://github.com/rojo-rbx/rojo) 7.6.1
- [Wally](https://github.com/UpliftGames/wally) 0.3.2
- [Rokit](https://github.com/rojo-rbx/rokit) (optional, for tool management)

### Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd <project-name>
```

2. **Install dependencies**
```bash
wally install
```

3. **Build the place file**
```bash
rojo build -o "WCS.rbxlx"
```

4. **Open in Roblox Studio**
Open `WCS.rbxlx` in Roblox Studio

5. **Start live sync**
```bash
rojo serve
```

### Development Workflow

1. Make changes to `.luau` files in the `src/` directory
2. Rojo will automatically sync changes to Studio
3. Test in Studio play mode
4. Commit changes to Git

## Current Development Status

### ✅ Completed
- WCS framework integration
- Basic project structure
- Character spawning and lifecycle management
- Example combat skill (Punch)
- Example status effect (Stun)
- Example moveset (Unarmed)

### 🚧 In Progress
- Input handling system
- Hitbox detection for combat

### 📋 Planned
- Permadeath system implementation
- Character slot management
- Lives system
- Faction selection UI
- Clan system
- Character data persistence
- Monetization integration

## Code Standards

### Naming Conventions
- **Files**: `lowercase.luau`
- **Classes/Modules**: `PascalCase`
- **Variables/Functions**: `camelCase`
- **Constants**: `UPPER_SNAKE_CASE`

### File Organization
- Server-only code in `src/server/`
- Client-only code in `src/client/`
- Shared code (skills, movesets, utilities) in `src/shared/`

### Performance Guidelines
- Minimize remote calls
- Use object pooling for frequently created instances
- Implement efficient hitbox detection
- Profile code regularly for bottlenecks

## Contributing

(Guidelines to be added as team expands)

## License

(To be determined)

## Resources

- [WCS Documentation](https://wcs-docs.vercel.app/)
- [Rojo Documentation](https://rojo.space/docs)
- [Luau Documentation](https://luau-lang.org/)
- [Wally Package Index](https://wally.run/)
