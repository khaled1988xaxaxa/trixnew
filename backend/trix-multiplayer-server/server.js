const WebSocket = require('ws');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 8080;

// Security middleware
app.use(helmet());
app.use(compression());
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:3000',
  credentials: true
}));

// Logging
app.use(morgan('combined'));

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Create HTTP server
const server = require('http').createServer(app);

// Create WebSocket server
const wss = new WebSocket.Server({ server });

// Game state management
const rooms = new Map();
const players = new Map();
const connections = new Map();

// Game logic
const GameManager = {
  // Create a new room
  createRoom(hostId, roomName, settings) {
    const roomId = uuidv4();
    const room = {
      id: roomId,
      name: roomName,
      hostId: hostId,
      players: [],
      status: 'waiting',
      settings: settings,
      createdAt: new Date(),
      currentGame: null,
      currentGameId: null,
    };
    
    rooms.set(roomId, room);
    return room;
  },

  // Join a room
  joinRoom(playerId, roomId, password) {
    const room = rooms.get(roomId);
    if (!room) {
      throw new Error('Room not found');
    }

    // Check if room has space for human players
    const humanPlayers = room.players.filter(p => !p.isAI);
    if (humanPlayers.length >= room.settings.maxPlayers) {
      throw new Error('Room is full of human players');
    }

    // If room is at max capacity but has AI bots, replace one AI bot
    if (room.players.length >= room.settings.maxPlayers) {
      const aiBotToReplace = room.players.find(p => p.isAI);
      if (aiBotToReplace) {
        // Remove AI bot from room and players map
        const aiIndex = room.players.findIndex(p => p.id === aiBotToReplace.id);
        room.players.splice(aiIndex, 1);
        players.delete(aiBotToReplace.id);
        console.log(`🤖 Replaced AI bot ${aiBotToReplace.name} with human player`);
      } else {
        throw new Error('Room is full');
      }
    }

    if (room.status !== 'waiting') {
      throw new Error('Game already in progress');
    }

    if (room.settings.password && room.settings.password !== password) {
      throw new Error('Invalid password');
    }

    const player = players.get(playerId);
    if (!player) {
      throw new Error('Player not found');
    }

    // Assign position if not already assigned
    if (!player.position) {
      const positions = ['south', 'west', 'north', 'east'];
      const usedPositions = room.players.map(p => p.position);
      const availablePositions = positions.filter(p => !usedPositions.includes(p));
      
      if (availablePositions.length > 0) {
        player.position = availablePositions[0];
      }
    }

    room.players.push(player);
    player.roomId = roomId;
    player.isReady = false;

    return room;
  },

  // Leave a room
  leaveRoom(playerId, roomId) {
    const room = rooms.get(roomId);
    if (!room) {
      throw new Error('Room not found');
    }

    const playerIndex = room.players.findIndex(p => p.id === playerId);
    if (playerIndex === -1) {
      throw new Error('Player not in room');
    }

    room.players.splice(playerIndex, 1);
    const player = players.get(playerId);
    if (player) {
      player.roomId = null;
      player.position = null;
      player.isReady = false;
    }

    // If room is empty, delete it
    if (room.players.length === 0) {
      rooms.delete(roomId);
    } else if (room.hostId === playerId) {
      // Transfer host to next player
      room.hostId = room.players[0].id;
      room.players[0].isHost = true;
    }

    return room;
  },

  // Start a game
  startGame(roomId) {
    const room = rooms.get(roomId);
    if (!room) {
      throw new Error('Room not found');
    }

    if (room.players.length < 2) {
      throw new Error('Need at least 2 players to start');
    }

    if (room.status !== 'waiting') {
      throw new Error('Game already in progress');
    }

    // Create game state
    const gameId = uuidv4();
    const gameState = this.createGameState(room, gameId);
    
    room.currentGame = gameState;
    room.currentGameId = gameId;
    room.status = 'playing';

    return gameState;
  },

  // Create initial game state
  createGameState(room, gameId) {
    // Initialize game with 4 players
    const playerHands = {};
    const scores = {};
    
    room.players.forEach(player => {
      playerHands[player.position] = [];
      scores[player.position] = 0;
    });

    return {
      gameId: gameId,
      roomId: room.id,
      phase: 'contractSelection',
      currentContract: null,
      currentPlayer: 'south',
      currentKing: 'south',
      round: 1,
      kingdom: 1,
      scores: scores,
      playerHands: playerHands,
      currentTrick: null,
      completedTricks: [],
      lastUpdated: new Date(),
      metadata: {},
    };
  },

  // Play a card
  playCard(playerId, roomId, card) {
    const room = rooms.get(roomId);
    if (!room || !room.currentGame) {
      throw new Error('No active game');
    }

    const player = players.get(playerId);
    if (!player || player.roomId !== roomId) {
      throw new Error('Player not in room');
    }

    // Validate card play
    // This is a simplified version - you'll need to implement full game logic
    const gameState = room.currentGame;
    
    // Remove card from player's hand
    const playerHand = gameState.playerHands[player.position];
    const cardIndex = playerHand.findIndex(c => 
      c.suit === card.suit && c.rank === card.rank
    );
    
    if (cardIndex === -1) {
      throw new Error('Card not in hand');
    }

    playerHand.splice(cardIndex, 1);

    // Update game state
    gameState.lastUpdated = new Date();

    return gameState;
  },

  // Select contract
  selectContract(playerId, roomId, contract) {
    const room = rooms.get(roomId);
    if (!room || !room.currentGame) {
      throw new Error('No active game');
    }

    const gameState = room.currentGame;
    gameState.currentContract = contract;
    gameState.phase = 'playing';
    gameState.lastUpdated = new Date();

    return gameState;
  },

  // Create AI bot
  createAIBot(roomId, botName) {
    const botId = `ai_${uuidv4()}`;
    const room = rooms.get(roomId);
    if (!room) {
      throw new Error('Room not found');
    }

    // Assign position for AI bot
    const positions = ['south', 'west', 'north', 'east'];
    const usedPositions = room.players.map(p => p.position);
    const availablePositions = positions.filter(p => !usedPositions.includes(p));
    
    if (availablePositions.length === 0) {
      throw new Error('No available positions for AI bot');
    }

    const aiBot = {
      id: botId,
      name: botName || `AI Bot ${availablePositions[0]}`,
      avatarUrl: null,
      position: availablePositions[0],
      roomId: roomId,
      status: 'connected',
      isReady: true, // AI bots are always ready
      isHost: false,
      isAI: true, // Mark as AI bot
      joinedAt: new Date(),
      lastSeen: new Date(),
    };

    // Add to players map and room
    players.set(botId, aiBot);
    room.players.push(aiBot);

    console.log(`🤖 AI bot ${aiBot.name} joined room ${room.name} at position ${aiBot.position}`);
    return aiBot;
  },

  // Fill room with AI bots up to maxPlayers
  fillWithAIBots(roomId) {
    const room = rooms.get(roomId);
    if (!room || !room.settings.allowAI) {
      return;
    }

    const currentPlayerCount = room.players.length;
    const maxPlayers = room.settings.maxPlayers;
    const botsToAdd = Math.min(maxPlayers - currentPlayerCount, 3); // Leave at least 1 human

    const botNames = ['AI Strategist', 'AI Challenger', 'AI Master'];
    
    for (let i = 0; i < botsToAdd; i++) {
      try {
        this.createAIBot(roomId, botNames[i]);
      } catch (error) {
        console.log(`❌ Could not add AI bot: ${error.message}`);
        break;
      }
    }

    if (botsToAdd > 0) {
      console.log(`🤖 Added ${botsToAdd} AI bots to room ${room.name}`);
    }
  },

  // Kick a player from room (host only)
  kickPlayer(hostId, roomId, targetPlayerId) {
    const room = rooms.get(roomId);
    if (!room) {
      throw new Error('Room not found');
    }

    // Check if the person kicking is the host
    if (room.hostId !== hostId) {
      throw new Error('Only the room host can kick players');
    }

    // Find the target player
    const targetPlayerIndex = room.players.findIndex(p => p.id === targetPlayerId);
    if (targetPlayerIndex === -1) {
      throw new Error('Player not found in room');
    }

    const targetPlayer = room.players[targetPlayerIndex];

    // Cannot kick yourself
    if (targetPlayerId === hostId) {
      throw new Error('Host cannot kick themselves');
    }

    // Remove player from room
    room.players.splice(targetPlayerIndex, 1);

    // If it's a human player, remove from players map and reset their room info
    if (!targetPlayer.isAI) {
      const player = players.get(targetPlayerId);
      if (player) {
        player.roomId = null;
        player.position = null;
        player.isReady = false;
        player.isHost = false;
      }
    } else {
      // If it's an AI bot, remove from players map completely
      players.delete(targetPlayerId);
    }

    console.log(`👢 Host ${hostId} kicked ${targetPlayer.isAI ? 'AI bot' : 'player'} ${targetPlayer.name} from room ${room.name}`);
    
    return {
      room: room,
      kickedPlayer: targetPlayer
    };
  },
};

// WebSocket connection handling
wss.on('connection', (ws, req) => {
  const connectionId = uuidv4();
  let playerId = null; // Will be set when first message is received
  
  connections.set(connectionId, { ws, playerId });

  console.log(`🔌 New connection: ${connectionId}`);

  // Send welcome message
  ws.send(JSON.stringify({
    id: uuidv4(),
    type: 'welcome',
    senderId: 'server',
    roomId: '',
    data: {
      playerId: playerId,
      message: 'Welcome to Trix Multiplayer!'
    },
    timestamp: new Date().toISOString()
  }));

  // Handle messages
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      handleMessage(connectionId, message);
    } catch (error) {
      console.error('Error handling message:', error);
      sendError(ws, 'Invalid message format');
    }
  });

  // Handle disconnection
  ws.on('close', () => {
    handleDisconnection(connectionId);
  });

  // Handle errors
  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    handleDisconnection(connectionId);
  });
});

// Message handling
function handleMessage(connectionId, message) {
  const connection = connections.get(connectionId);
  if (!connection) return;

  let { ws, playerId } = connection;
  
  // If this is the first message, establish the player using client's ID
  if (!playerId && message.senderId) {
    playerId = message.senderId;
    connection.playerId = playerId;
    
    // Create player if it doesn't exist
    if (!players.has(playerId)) {
      const player = {
        id: playerId,
        name: message.data?.playerName || `Player_${playerId.substring(0, 8)}`,
        avatarUrl: null,
        position: null,
        roomId: null,
        status: 'connected',
        isReady: false,
        isHost: false,
        isAI: false,
        joinedAt: new Date(),
        lastSeen: new Date(),
      };
      
      players.set(playerId, player);
      console.log(`🎮 Player established: ${playerId} (${player.name})`);
    }
  }

  const player = players.get(playerId);

  if (!player) {
    sendError(ws, 'Player not found');
    return;
  }

  // Update last seen
  player.lastSeen = new Date();
  
  // Debug logging for message handling
  console.log(`📥 Handling message from ${playerId}: ${message.type} (ID: ${message.id})`);
  if (message.type === 'createRoom') {
    console.log(`📋 CreateRoom data:`, JSON.stringify(message.data, null, 2));
  }

  try {
    switch (message.type) {
      case 'createRoom':
        handleCreateRoom(ws, playerId, message);
        break;
      case 'joinRoom':
        handleJoinRoom(ws, playerId, message);
        break;
      case 'leaveRoom':
        handleLeaveRoom(ws, playerId, message);
        break;
      case 'kickPlayer':
        handleKickPlayer(ws, playerId, message);
        break;
      case 'getRooms':
        handleGetRooms(ws, playerId, message);
        break;
      case 'startGame':
        handleStartGame(ws, playerId, message);
        break;
      case 'playCard':
        handlePlayCard(ws, playerId, message);
        break;
      case 'selectContract':
        handleSelectContract(ws, playerId, message);
        break;
      case 'chatMessage':
        handleChatMessage(ws, playerId, message);
        break;
      case 'playerReady':
        handlePlayerReady(ws, playerId, message);
        break;
      case 'ping':
        handlePing(ws, playerId, message);
        break;
      default:
        sendError(ws, `Unknown message type: ${message.type}`);
    }
  } catch (error) {
    console.error('Error handling message:', error);
    sendError(ws, error.message);
  }
}

// Message handlers
function handleCreateRoom(ws, playerId, message) {
  const { roomName, name, settings } = message.data;
  const roomTitle = roomName || name; // Support both 'roomName' and 'name' for compatibility
  
  console.log(`🏠 Creating room "${roomTitle}" by player ${playerId}`);
  
  // Ensure settings has required fields with defaults
  const roomSettings = {
    maxPlayers: 4,
    allowSpectators: false,
    autoStart: true,
    allowAI: true,
    aiCount: 0,
    enableChat: true,
    enableVoice: false,
    password: null,
    ...settings // Override with provided settings
  };
  
  const room = GameManager.createRoom(playerId, roomTitle, roomSettings);
  
  // Join the room
  GameManager.joinRoom(playerId, room.id);
  
  // Update player as host
  const player = players.get(playerId);
  player.isHost = true;
  player.position = 'south';

  console.log(`🏠 Room created successfully: ${room.id} by ${playerId}`);
  console.log(`📊 Total rooms now: ${rooms.size}`);

  // Fill room with AI bots if enabled
  if (roomSettings.allowAI) {
    GameManager.fillWithAIBots(room.id);
  }

  // Send response
  sendResponse(ws, message.id, {
    success: true,
    room: room
  });

  // Broadcast room update
  broadcastToRoom(room.id, {
    id: uuidv4(),
    type: 'roomUpdate',
    senderId: 'server',
    roomId: room.id,
    data: { room: room },
    timestamp: new Date().toISOString()
  });
}

function handleJoinRoom(ws, playerId, message) {
  const { roomId, password } = message.data;
  
  console.log(`🔍 Join room attempt: Player ${playerId} trying to join room ${roomId}`);
  console.log(`📊 Available rooms: ${Array.from(rooms.keys())}`);
  
  try {
    const room = GameManager.joinRoom(playerId, roomId, password);

    console.log(`👥 Player ${playerId} successfully joined room ${roomId}`);

    // Fill with AI bots if there's still space and AI is enabled
    if (room.settings.allowAI && room.players.length < room.settings.maxPlayers) {
      GameManager.fillWithAIBots(roomId);
      // Get updated room after adding bots
      const updatedRoom = rooms.get(roomId);
      room.players = updatedRoom.players;
    }

    // Send response
    sendResponse(ws, message.id, {
      success: true,
      room: room
    });

    // Broadcast room update
    broadcastToRoom(roomId, {
      id: uuidv4(),
      type: 'roomUpdate',
      senderId: 'server',
      roomId: roomId,
      data: { room: room },
      timestamp: new Date().toISOString()
    });

    // Broadcast player joined
    broadcastToRoom(roomId, {
      id: uuidv4(),
      type: 'playerJoined',
      senderId: 'server',
      roomId: roomId,
      data: { 
        playerId: playerId,
        playerName: players.get(playerId).name
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.log(`❌ Failed to join room ${roomId}: ${error.message}`);
    sendError(ws, error.message);
  }
}

function handleLeaveRoom(ws, playerId, message) {
  const { roomId } = message.data;
  const room = GameManager.leaveRoom(playerId, roomId);

  console.log(`👋 Player ${playerId} left room ${roomId}`);

  // Send response
  sendResponse(ws, message.id, {
    success: true
  });

  // Broadcast room update
  if (room) {
    broadcastToRoom(roomId, {
      id: uuidv4(),
      type: 'roomUpdate',
      senderId: 'server',
      roomId: roomId,
      data: { room: room },
      timestamp: new Date().toISOString()
    });
  }

  // Broadcast player left
  broadcastToRoom(roomId, {
    id: uuidv4(),
    type: 'playerLeft',
    senderId: 'server',
    roomId: roomId,
    data: { 
      playerId: playerId,
      playerName: players.get(playerId).name
    },
    timestamp: new Date().toISOString()
  });
}

function handleKickPlayer(ws, playerId, message) {
  const { roomId, targetPlayerId } = message.data;
  
  try {
    const result = GameManager.kickPlayer(playerId, roomId, targetPlayerId);
    const { room, kickedPlayer } = result;

    // Send success response to host
    sendResponse(ws, message.id, {
      success: true,
      kickedPlayer: {
        id: kickedPlayer.id,
        name: kickedPlayer.name,
        isAI: kickedPlayer.isAI
      }
    });

    // If kicked player is human, notify them
    if (!kickedPlayer.isAI) {
      const kickedConnection = Array.from(connections.values())
        .find(conn => conn.playerId === targetPlayerId);
      
      if (kickedConnection) {
        kickedConnection.ws.send(JSON.stringify({
          id: uuidv4(),
          type: 'kicked',
          senderId: 'server',
          roomId: roomId,
          data: { 
            reason: 'You were kicked from the room by the host',
            roomName: room.name
          },
          timestamp: new Date().toISOString()
        }));
      }
    }

    // Broadcast room update to remaining players
    broadcastToRoom(roomId, {
      id: uuidv4(),
      type: 'roomUpdate',
      senderId: 'server',
      roomId: roomId,
      data: { room: room },
      timestamp: new Date().toISOString()
    });

    // Broadcast player kicked notification
    broadcastToRoom(roomId, {
      id: uuidv4(),
      type: 'playerKicked',
      senderId: 'server',
      roomId: roomId,
      data: { 
        kickedPlayerId: targetPlayerId,
        kickedPlayerName: kickedPlayer.name,
        isAI: kickedPlayer.isAI,
        kickedBy: players.get(playerId)?.name || 'Host'
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.log(`❌ Failed to kick player: ${error.message}`);
    sendError(ws, error.message);
  }
}

function handleGetRooms(ws, playerId, message) {
  const availableRooms = Array.from(rooms.values())
    .filter(room => {
      if (room.status !== 'waiting') return false;
      
      // Count human players (non-AI)
      const humanPlayers = room.players.filter(p => !p.isAI).length;
      
      // Room is available if it has space for more human players
      // We allow up to maxPlayers-1 human players (leaving room for AI)
      return humanPlayers < room.settings.maxPlayers;
    })
    .map(room => ({
      id: room.id,
      name: room.name,
      hostId: room.hostId,
      players: room.players,
      status: room.status,
      createdAt: room.createdAt,
      settings: room.settings,
      currentGameId: room.currentGameId,
    }));

  console.log(`📋 Player ${playerId} requested rooms list. Available: ${availableRooms.length}/${rooms.size} total rooms`);
  availableRooms.forEach(room => {
    console.log(`  📄 Room: ${room.name} (${room.id}) - ${room.players.length}/${room.settings.maxPlayers} players`);
  });

  sendResponse(ws, message.id, {
    success: true,
    rooms: availableRooms
  });
}

function handleStartGame(ws, playerId, message) {
  const { roomId } = message.data;
  const room = rooms.get(roomId);
  
  if (!room || room.hostId !== playerId) {
    throw new Error('Only host can start game');
  }

  const gameState = GameManager.startGame(roomId);

  console.log(`🎮 Game started in room ${roomId}`);

  // Send success response to the host
  sendResponse(ws, message.id, {
    success: true,
    message: 'Game started successfully',
    gameState: gameState
  });

  // Broadcast game start to all players
  broadcastToRoom(roomId, {
    id: uuidv4(),
    type: 'gameStarted',
    senderId: 'server',
    roomId: roomId,
    data: { 
      gameState: gameState,
      message: 'Game has started!'
    },
    timestamp: new Date().toISOString()
  });
}

function handlePlayCard(ws, playerId, message) {
  const { roomId, card, gameId } = message.data;
  const gameState = GameManager.playCard(playerId, roomId, card);

  // Broadcast game state update
  broadcastToRoom(roomId, {
    id: uuidv4(),
    type: 'gameStateUpdate',
    senderId: 'server',
    roomId: roomId,
    data: { gameState: gameState },
    timestamp: new Date().toISOString()
  });
}

function handleSelectContract(ws, playerId, message) {
  const { roomId, contract, gameId } = message.data;
  const gameState = GameManager.selectContract(playerId, roomId, contract);

  // Broadcast game state update
  broadcastToRoom(roomId, {
    id: uuidv4(),
    type: 'gameStateUpdate',
    senderId: 'server',
    roomId: roomId,
    data: { gameState: gameState },
    timestamp: new Date().toISOString()
  });
}

function handleChatMessage(ws, playerId, message) {
  const { roomId } = message.data;
  const player = players.get(playerId);

  // Broadcast chat message
  broadcastToRoom(roomId, {
    id: uuidv4(),
    type: 'chatMessage',
    senderId: playerId,
    roomId: roomId,
    data: {
      message: message.data.message,
      playerName: player.name,
      timestamp: new Date().toISOString()
    },
    timestamp: new Date().toISOString()
  });
}

function handlePlayerReady(ws, playerId, message) {
  const { roomId, isReady } = message.data;
  const player = players.get(playerId);
  
  console.log(`🔄 Player ${playerId} setting ready status to ${isReady} in room ${roomId}`);
  
  if (player && player.roomId === roomId) {
    player.isReady = isReady;
    
    console.log(`✅ Player ${player.name} is now ${isReady ? 'ready' : 'not ready'}`);
    
    const room = rooms.get(roomId);
    if (room) {
      // Broadcast room update
      broadcastToRoom(roomId, {
        id: uuidv4(),
        type: 'roomUpdate',
        senderId: 'server',
        roomId: roomId,
        data: { room: room },
        timestamp: new Date().toISOString()
      });
      
      console.log(`📡 Broadcasted room update for ${room.name}`);
      
      // Check if all players are ready and start game automatically
      const allPlayersReady = room.players.every(p => p.isReady);
      const hasEnoughPlayers = room.players.length >= 2; // Minimum 2 players for testing
      
      if (allPlayersReady && hasEnoughPlayers && !room.currentGame) {
        console.log(`🎮 All players ready in room ${room.name}! Starting game...`);
        
        try {
          const gameState = GameManager.startGame(roomId);
          
          // Broadcast game started
          broadcastToRoom(roomId, {
            id: uuidv4(),
            type: 'gameStarted',
            senderId: 'server',
            roomId: roomId,
            data: { 
              gameState: gameState,
              message: 'Game has started! Good luck!' 
            },
            timestamp: new Date().toISOString()
          });
          
          console.log(`🚀 Game started in room ${room.name} with ${room.players.length} players`);
        } catch (error) {
          console.error(`❌ Failed to start game in room ${roomId}:`, error);
          
          // Broadcast error to room
          broadcastToRoom(roomId, {
            id: uuidv4(),
            type: 'error',
            senderId: 'server',
            roomId: roomId,
            data: { 
              error: 'Failed to start game',
              message: error.message 
            },
            timestamp: new Date().toISOString()
          });
        }
      }
    }
  } else {
    console.log(`❌ Player ${playerId} not found or not in room ${roomId}`);
  }
}

function handlePing(ws, playerId, message) {
  // Send pong response
  ws.send(JSON.stringify({
    id: uuidv4(),
    type: 'pong',
    senderId: 'server',
    roomId: message.roomId || '',
    data: {},
    timestamp: new Date().toISOString()
  }));
}

// Utility functions
function sendResponse(ws, messageId, data) {
  const response = {
    id: uuidv4(),
    type: 'response',
    senderId: 'server',
    roomId: '',
    data: {
      responseTo: messageId,
      ...data
    },
    timestamp: new Date().toISOString()
  };
  
  console.log(`📤 Sending response to ${messageId}:`, JSON.stringify(data, null, 2));
  ws.send(JSON.stringify(response));
}

function sendError(ws, error) {
  ws.send(JSON.stringify({
    id: uuidv4(),
    type: 'error',
    senderId: 'server',
    roomId: '',
    data: { error: error },
    timestamp: new Date().toISOString()
  }));
}

function broadcastToRoom(roomId, message) {
  const room = rooms.get(roomId);
  if (!room) return;

  room.players.forEach(player => {
    const connection = Array.from(connections.values())
      .find(conn => conn.playerId === player.id);
    
    if (connection && connection.ws.readyState === WebSocket.OPEN) {
      connection.ws.send(JSON.stringify(message));
    }
  });
}

function handleDisconnection(connectionId) {
  const connection = connections.get(connectionId);
  if (!connection) return;

  const { playerId } = connection;
  const player = players.get(playerId);

  if (player && player.roomId) {
    try {
      const room = GameManager.leaveRoom(playerId, player.roomId);
      
      // Broadcast room update
      if (room) {
        broadcastToRoom(player.roomId, {
          id: uuidv4(),
          type: 'roomUpdate',
          senderId: 'server',
          roomId: player.roomId,
          data: { room: room },
          timestamp: new Date().toISOString()
        });
      }

      // Broadcast player left
      broadcastToRoom(player.roomId, {
        id: uuidv4(),
        type: 'playerLeft',
        senderId: 'server',
        roomId: player.roomId,
        data: { 
          playerId: playerId,
          playerName: player.name
        },
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      console.error('Error handling disconnection:', error);
    }
  }

  // Clean up
  players.delete(playerId);
  connections.delete(connectionId);

  console.log(`🔌 Player disconnected: ${playerId}`);
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    connections: connections.size,
    players: players.size,
    rooms: rooms.size
  });
});

// Start server
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Trix Multiplayer Server running on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`🌐 WebSocket: ws://localhost:${PORT}`);
  console.log(`📱 Android/External: ws://192.168.0.80:${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('🛑 Shutting down server...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('🛑 Shutting down server...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
});
