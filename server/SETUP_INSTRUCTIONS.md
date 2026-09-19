# Setup Instructions for FastAPI Backend with PostgreSQL

## Step 1: Install Python
Make sure you have Python 3.8+ installed. Download from https://www.python.org/

## Step 2: Install Python Dependencies
Open a terminal in the `server` folder and run:
```bash
cd server
pip install -r requirements.txt
```

Or if you're using Python 3 specifically:
```bash
pip3 install -r requirements.txt
```

## Step 3: Configure PostgreSQL

1. Make sure PostgreSQL is running on your computer
2. Open PostgreSQL (pgAdmin or psql command line)
3. Create a new database:
```sql
CREATE DATABASE homeguardian;
```

4. Note your PostgreSQL credentials:
   - Username (usually `postgres`)
   - Password (the one you set during installation)
   - Port (usually `5432`)

## Step 4: Configure Environment Variables

1. In the `server` folder, create a `.env` file (copy from `.env.example` if needed)
2. Update the `.env` file with your PostgreSQL credentials:
```
DB_USER=postgres
DB_HOST=localhost
DB_NAME=homeguardian
DB_PASSWORD=your_password_here
DB_PORT=5432
PORT=3000
```

## Step 5: Start the FastAPI Server

In the `server` folder, run:
```bash
python main.py
```

Or:
```bash
python3 main.py
```

Or using uvicorn directly:
```bash
uvicorn main:app --host 0.0.0.0 --port 3000 --reload
```

You should see:
```
Users table ready
INFO:     Uvicorn running on http://0.0.0.0:3000
```

The `--reload` flag enables auto-reload during development.

## Step 6: Access API Documentation

FastAPI provides automatic interactive API documentation:
- Swagger UI: http://localhost:3000/docs
- ReDoc: http://localhost:3000/redoc

## Step 7: Update Flutter App API URL

In `lib/pages/signup_page.dart`, update the `apiBaseUrl` based on where you're running the app:

- **Android Emulator**: `http://10.0.2.2:3000` (already set)
- **iOS Simulator**: `http://localhost:3000`
- **Physical Device**: Use your computer's IP address (e.g., `http://192.168.1.100:3000`)

To find your computer's IP:
- Windows: Run `ipconfig` in CMD, look for IPv4 Address
- Mac/Linux: Run `ifconfig` or `ip addr`

## Step 8: Test the Connection

1. Make sure the FastAPI server is running
2. Run your Flutter app
3. Go to Sign Up page
4. Enter your name and click "Scan Face"
5. You should see a success message and the name will be saved to PostgreSQL

## Troubleshooting

- **Connection Error**: Make sure the FastAPI server is running and the API URL is correct
- **Database Error**: Check your PostgreSQL credentials in the `.env` file
- **Port Already in Use**: Change the PORT in `.env` to a different number (e.g., 3001)
- **Module Not Found**: Make sure you've installed all requirements: `pip install -r requirements.txt`
- **psycopg2 Error**: On some systems, you may need to install PostgreSQL development libraries:
  - Windows: Usually included with PostgreSQL installation
  - Mac: `brew install postgresql`
  - Linux: `sudo apt-get install libpq-dev` (Ubuntu/Debian) or `sudo yum install postgresql-devel` (CentOS/RHEL)

## API Endpoints

- `GET /api/health` - Health check
- `POST /api/users` - Create a new user (requires `name` in body)
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
