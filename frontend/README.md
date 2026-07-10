# Monoton Frontend

React + TypeScript frontend for the Monoton B2B Invoice Settlement platform.

## Features

- React 18 with TypeScript
- React Router for navigation
- React Context for state management
- OpenAPI client for backend communication
- Vite for fast development

## Setup

```bash
npm install
```

## Development

```bash
npm run dev
```

## Build

```bash
npm run build
```

## Architecture

- `src/views/` - Page components (Home, Invoices, Wallet, etc.)
- `src/stores/` - React Context stores for state management
- `src/components/` - Reusable UI components
- `src/utils/` - Utility functions
- `common/` - OpenAPI specification for backend API

## API Integration

The frontend communicates with the backend via the REST API. The API types are generated from `common/openapi.yaml`.

## License

Apache-2.0
