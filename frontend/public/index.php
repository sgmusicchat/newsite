<?php
/**
 * Homepage - Event Listing
 * Purpose: Display 7-day upcoming events from Gold layer
 * Performance: Gold reads only, <100ms target
 */

require_once '../includes/config.php';
require_once '../includes/persona_helper.php';

// Load persona theme (server-side, no JS)
$persona_theme = get_persona_theme();

// Query Gold layer (v_live_events VIEW for zero-downtime)
$sql = "
    SELECT
        event_id,
        event_name,
        venue_name,
        venue_slug,
        event_date,
        start_time,
        genres_concat,
        price_min,
        price_max,
        is_free,
        image_url,
        ticket_url
    FROM v_live_events
    WHERE event_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
    ORDER BY event_date ASC, start_time ASC
    LIMIT 50
";

$stmt = $pdo_gold->prepare($sql);
$stmt->execute();
$events = $stmt->fetchAll();

// Get genre stats for sidebar
$sql_genres = "
    SELECT genre_name, upcoming_event_count
    FROM gold_genre_stats
    WHERE upcoming_event_count > 0
    ORDER BY upcoming_event_count DESC
    LIMIT 10
";
$stmt_genres = $pdo_gold->prepare($sql_genres);
$stmt_genres->execute();
$popular_genres = $stmt_genres->fetchAll();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>r/sgmusicchat - Singapore Electronic Music Events</title>
    <!-- Persona Synth CSS -->
    <link rel="stylesheet" href="/assets/css/persona-synth.css">
    <!-- Persona Theme (Server-Side) -->
    <style>
        <?php echo render_persona_theme_css($persona_theme); ?>
    </style>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: var(--persona-font, 'Courier New'), monospace; 
            background: var(--persona-bg, #000); 
            color: var(--persona-accent, #0f0); 
            padding: 20px; 
        }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: var(--persona-accent, #0f0); margin-bottom: 20px; font-size: 24px; }
        .header { border: var(--persona-border, 2px solid #0f0); padding-bottom: 10px; margin-bottom: 20px; }
        .nav { margin-bottom: 20px; }
        .nav a { color: var(--persona-accent, #0f0); margin-right: 20px; text-decoration: none; }
        .nav a:hover { text-decoration: underline; }
        .main-content { display: flex; gap: 40px; }
        .events { flex: 3; }
        .sidebar { flex: 1; }
        .event { border: var(--persona-border, 1px solid #0f0); padding: 15px; margin-bottom: 15px; }
        .event-date { color: var(--persona-accent, #ff0); font-weight: bold; }
        .event-name { color: var(--persona-accent, #0ff); font-size: 18px; margin: 5px 0; }
        .event-venue { color: var(--persona-accent, #0f0); }
        .event-genres { color: var(--persona-accent, #f0f); font-size: 12px; margin: 5px 0; }
        .event-price { color: var(--persona-accent, #fff); margin: 5px 0; }
        .event-free { color: var(--persona-accent, #ff0); font-weight: bold; }
        .sidebar-box { border: var(--persona-border, 1px solid #0f0); padding: 15px; margin-bottom: 20px; }
        .sidebar-box h3 { color: var(--persona-accent, #0ff); margin-bottom: 10px; font-size: 16px; }
        .genre-item { margin: 5px 0; font-size: 14px; }
        .no-events { color: var(--persona-accent, #f00); padding: 20px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>r/sgmusicchat</h1>
            <p>Singapore Electronic Music Events (Next 7 Days)</p>
        </div>

        <div class="nav">
            <a href="/index.php">Home</a>
            <a href="/search.php">Search</a>
            <a href="/submit.php">Submit Event</a>
            <a href="/admin/">Admin</a>
        </div>

        <!-- Persona Synth Trigger -->
        <div class="persona-synth-trigger">
            <button id="persona-init-btn" class="retro-btn">
                🎭 Initialize Your Digital Identity
            </button>
            <p style="font-size: 11px; color: #666; margin-top: 10px;">
                Generate your MySpace-style persona using AI
            </p>
        </div>

        <div class="main-content">
            <div class="events">
                <h2 style="color: #0ff; margin-bottom: 15px;">Upcoming Events (<?= count($events) ?>)</h2>

                <?php if (empty($events)): ?>
                    <div class="no-events">
                        No upcoming events in the next 7 days.<br>
                        <a href="/submit.php" style="color: #0ff;">Be the first to submit an event!</a>
                    </div>
                <?php else: ?>
                    <?php foreach ($events as $event): ?>
                        <div class="event">
                            <div class="event-date">
                                <?= date('D, M j Y', strtotime($event['event_date'])) ?>
                                <?= $event['start_time'] ? ' @ ' . date('g:i A', strtotime($event['start_time'])) : '' ?>
                            </div>
                            <div class="event-name"><?= htmlspecialchars($event['event_name']) ?></div>
                            <div class="event-venue">
                                📍 <?= htmlspecialchars($event['venue_name']) ?>
                            </div>
                            <?php if ($event['genres_concat']): ?>
                                <div class="event-genres">
                                    🎵 <?= htmlspecialchars($event['genres_concat']) ?>
                                </div>
                            <?php endif; ?>
                            <div class="event-price">
                                <?php if ($event['is_free']): ?>
                                    <span class="event-free">FREE ENTRY</span>
                                <?php else: ?>
                                    💰 SGD $<?= number_format($event['price_min'], 0) ?>
                                    <?php if ($event['price_max'] && $event['price_max'] > $event['price_min']): ?>
                                        - $<?= number_format($event['price_max'], 0) ?>
                                    <?php endif; ?>
                                <?php endif; ?>
                            </div>
                            <?php if ($event['ticket_url']): ?>
                                <div style="margin-top: 10px;">
                                    <a href="<?= htmlspecialchars($event['ticket_url']) ?>"
                                       target="_blank"
                                       style="color: #ff0; text-decoration: underline;">
                                        🎟️ Get Tickets
                                    </a>
                                </div>
                            <?php endif; ?>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>

            <div class="sidebar">
                <div class="sidebar-box">
                    <h3>Popular Genres</h3>
                    <?php foreach ($popular_genres as $genre): ?>
                        <div class="genre-item">
                            <a href="/search.php?genre=<?= urlencode($genre['genre_name']) ?>"
                               style="color: #0f0; text-decoration: none;">
                                <?= htmlspecialchars($genre['genre_name']) ?>
                                <span style="color: #fff;">(<?= $genre['upcoming_event_count'] ?>)</span>
                            </a>
                        </div>
                    <?php endforeach; ?>
                </div>

                <div class="sidebar-box">
                    <h3>About</h3>
                    <p style="font-size: 12px; line-height: 1.6;">
                        r/sgmusicchat aggregates electronic music events in Singapore.
                        Inspired by 19hz.info.
                    </p>
                    <p style="font-size: 12px; margin-top: 10px;">
                        <a href="/submit.php" style="color: #0ff;">Submit an event</a>
                    </p>
                </div>
            </div>
        </div>

        <div style="border-top: 1px solid #0f0; margin-top: 40px; padding-top: 20px; text-align: center; font-size: 12px; color: #666;">
            Powered by Gutsy Startup Architecture | Data refreshes hourly
        </div>
    </div>

    <!-- Persona Synth JavaScript -->
    <script src="/assets/js/persona-synth.js"></script>
</body>
</html>
