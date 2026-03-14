const express = require('express');
const AWS = require('aws-sdk');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { v4: uuidv4 } = require('uuid');
const client = require('prom-client');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// ── AWS Setup ──────────────────────────────────────────────
AWS.config.update({ region: process.env.AWS_REGION || 'ap-south-1' });
const s3 = new AWS.S3();
const dynamodb = new AWS.DynamoDB.DocumentClient();

const S3_BUCKET    = process.env.S3_BUCKET    || 'razors-edge-bookings';
const DYNAMO_TABLE = process.env.DYNAMO_TABLE  || 'razors-edge-appointments';

// ── Prometheus Metrics ─────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

const bookingsTotal = new client.Counter({
  name: 'bookings_total',
  help: 'Total bookings created',
  registers: [register]
});

const bookingDuration = new client.Histogram({
  name: 'booking_duration_seconds',
  help: 'Time taken to save a booking',
  buckets: [0.1, 0.5, 1, 2, 5],
  registers: [register]
});

// ── Middleware ─────────────────────────────────────────────
app.use(cors());
app.use(helmet({ contentSecurityPolicy: false }));
app.use(morgan('combined'));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Track requests
app.use((req, res, next) => {
  res.on('finish', () => {
    httpRequestsTotal.inc({ method: req.method, route: req.path, status: res.statusCode });
  });
  next();
});

// ── Routes ─────────────────────────────────────────────────

// Login page
app.get('/login', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

// Health check (used by Docker & monitoring)
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: "Razor's Edge API", timestamp: new Date().toISOString() });
});

// Prometheus metrics endpoint (scraped by Prometheus)
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// POST — Create Booking
app.post('/api/bookings', async (req, res) => {
  const end = bookingDuration.startTimer();
  try {
    const booking = {
      id:        uuidv4(),
      ...req.body,
      createdAt: new Date().toISOString(),
      status:    'confirmed'
    };

    // Save to DynamoDB
    await dynamodb.put({
      TableName: DYNAMO_TABLE,
      Item: booking
    }).promise();

    // Archive to S3
    const dateKey = booking.createdAt.split('T')[0];
    await s3.putObject({
      Bucket:      S3_BUCKET,
      Key:         `bookings/${dateKey}/${booking.id}.json`,
      Body:        JSON.stringify(booking, null, 2),
      ContentType: 'application/json'
    }).promise();

    bookingsTotal.inc();
    end();
    console.log(`✅ Booking saved: ${booking.id} — ${booking.name}`);
    res.json({ success: true, bookingId: booking.id });

  } catch (err) {
    end();
    console.error('❌ Booking error:', err.message);
    res.status(500).json({ success: false, error: 'Failed to save booking' });
  }
});

// GET — All Bookings
app.get('/api/bookings', async (req, res) => {
  try {
    const result = await dynamodb.scan({ TableName: DYNAMO_TABLE }).promise();
    const sorted = result.Items.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    res.json({ bookings: sorted, count: sorted.length });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch bookings' });
  }
});

// GET — Bookings by date
app.get('/api/bookings/date/:date', async (req, res) => {
  try {
    const result = await dynamodb.query({
      TableName: DYNAMO_TABLE,
      IndexName: 'DateIndex',
      KeyConditionExpression: '#d = :date',
      ExpressionAttributeNames: { '#d': 'date' },
      ExpressionAttributeValues: { ':date': req.params.date }
    }).promise();
    res.json({ bookings: result.Items });
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// Catch-all → login
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

app.listen(PORT, () => {
  console.log(`💈 Razor's Edge API running on http://localhost:${PORT}`);
});

module.exports = app;
