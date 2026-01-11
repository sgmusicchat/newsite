<?php
/**
 * Admin Login
 * Purpose: Simple bcrypt + session authentication
 */

require_once '../includes/config.php';

$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';

    if ($username === $admin_username && password_verify($password, $admin_password_hash)) {
        session_start();
        $_SESSION['admin_logged_in'] = true;
        $_SESSION['admin_username'] = $username;
        header('Location: /admin/index.php');
        exit;
    } else {
        $error = 'Invalid username or password';
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Login - r/sgmusicchat</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Courier New', monospace; background: #000; color: #0f0; display: flex; justify-content: center; align-items: center; height: 100vh; }
        .login-box { border: 2px solid #0f0; padding: 40px; width: 400px; }
        h1 { color: #0ff; margin-bottom: 30px; text-align: center; }
        .form-group { margin-bottom: 20px; }
        label { display: block; color: #0f0; margin-bottom: 5px; }
        input { width: 100%; padding: 10px; background: #111; color: #0f0; border: 1px solid #0f0; font-family: 'Courier New', monospace; }
        button { width: 100%; background: #0f0; color: #000; border: none; padding: 15px; font-size: 16px; font-weight: bold; cursor: pointer; font-family: 'Courier New', monospace; }
        button:hover { background: #0ff; }
        .error { background: #f00; color: #fff; padding: 10px; margin-bottom: 20px; text-align: center; }
        .back { text-align: center; margin-top: 20px; }
        .back a { color: #0f0; text-decoration: none; }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>Admin Login</h1>

        <?php if ($error): ?>
            <div class="error"><?= htmlspecialchars($error) ?></div>
        <?php endif; ?>

        <form method="POST">
            <div class="form-group">
                <label>Username</label>
                <input type="text" name="username" required autofocus>
            </div>

            <div class="form-group">
                <label>Password</label>
                <input type="password" name="password" required>
            </div>

            <button type="submit">Login</button>
        </form>

        <div class="back">
            <a href="/index.php">← Back to Site</a>
        </div>
    </div>
</body>
</html>
