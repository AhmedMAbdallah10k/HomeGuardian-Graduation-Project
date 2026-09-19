# HomeGuardian Backend Server

A simple Node.js backend server for the HomeGuardian Flutter application.

## Setup

1. Install dependencies:
```bash
npm install
```

2. Create a `.env` file based on `.env.example` and update with your PostgreSQL credentials:
```bash
cp .env.example .env
```

3. Make sure PostgreSQL is running and create a database:
```sql
CREATE DATABASE homeguardian;
```

4. Start the server:
```bash
npm start
```

For development with auto-reload:
```bash
npm run dev
```

## API Endpoints

- `GET /api/health` - Health check
- `POST /api/users` - Save a new user (requires `name` in body)
- `GET /api/users` - Get all users

## Example Request

```bash
POST http://localhost:3000/api/users
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john@example.com",
  "phone": "1234567890"
}
```

