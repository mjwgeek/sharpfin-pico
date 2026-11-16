<?php
/**
 * Revo Pico / Sharpfin radio-station bridge v0.3 — expanded genres and pages.
 * PHP 7.4+, cURL; XMLReader + SimpleXML for ?source=xiph.
 * Output: #EXTM3U, #EXTGRP:Rock, #EXTINF:Station, URL.
 * Genre continuation groups are automatically named Rock 2, Rock 3, etc.
 * With Pico's existing v0.5 genre-folder importer these appear as Rock_2,
 * Rock_3 on disk, with <=40 stations in each playlist (importer limit: 50).
 * No changes to firmware, radio configuration, or other station playlists.
 *
 * GET ?source=radio&country=US (default) | ?source=radio&country=ALL
 * GET ?source=xiph (Icecast's public MP3 station listings)
 * No official SHOUTcast API is used.
 * All emitted station links use HTTP for legacy Pico playback.
 * Note: an HTTPS-only stream may still fail or redirect to HTTPS.
 */
error_reporting(0);
ini_set('display_errors', '0');

const PICO_FEED_VERSION = '0.3.1';
const PICO_MAX_BYTES = 275000;       // safely below the Pico importer 300000-byte cap
const PICO_MAX_STATIONS = 1900;     // total, to keep UPnP browsing manageable
const PICO_STATIONS_PER_FOLDER = 40; // below the Pico importer's 50-per-folder limit
const PICO_CACHE_SECONDS = 21600;   // six hours; avoid hammering public directories
const PICO_MAX_GENRE_POOL = 160;

/** Key: human-readable folder name. Value: Radio Browser tag; prefer=true
 * genres may receive extra stations after each available genre has a first page.
 * Keep names ASCII and <=33 chars so " 2" fits the Pico's 40-char group limit.
 */
function pico_genres() {
    return array(
        'Rock' => array('rock', true),
        'Classic Rock' => array('classic rock', true),
        'Hard Rock' => array('hard rock', false),
        'Alternative' => array('alternative', false),
        'Indie' => array('indie', false),
        'Metal' => array('metal', true),
        'Punk' => array('punk', false),
        'Pop' => array('pop', true),
        'Top 40' => array('top 40', false),
        'Hits' => array('hits', false),
        'Soft Rock' => array('soft rock', false),
        'Adult Contemporary' => array('adult contemporary', false),
        'Oldies' => array('oldies', true),
        '50s' => array('50s', false),
        '60s' => array('60s', false),
        '70s' => array('70s', false),
        '80s' => array('80s', true),
        '90s' => array('90s', false),
        '2000s' => array('2000s', false),
        'Country' => array('country', true),
        'Bluegrass' => array('bluegrass', false),
        'Americana' => array('americana', false),
        'Folk' => array('folk', false),
        'Blues' => array('blues', true),
        'Jazz' => array('jazz', true),
        'Smooth Jazz' => array('smooth jazz', false),
        'Classical' => array('classical', true),
        'Opera' => array('opera', false),
        'Easy Listening' => array('easy listening', false),
        'R and B' => array('r&b', false),
        'Soul' => array('soul', false),
        'Funk' => array('funk', false),
        'Disco' => array('disco', false),
        'Hip Hop' => array('hip hop', true),
        'Rap' => array('rap', false),
        'Electronic' => array('electronic', true),
        'Dance' => array('dance', false),
        'EDM' => array('edm', false),
        'House' => array('house', false),
        'Techno' => array('techno', false),
        'Trance' => array('trance', false),
        'Ambient' => array('ambient', false),
        'Chillout' => array('chillout', false),
        'Lounge' => array('lounge', false),
        'Reggae' => array('reggae', false),
        'Ska' => array('ska', false),
        'Latin' => array('latin', true),
        'Salsa' => array('salsa', false),
        'Tropical' => array('tropical', false),
        'World' => array('world', false),
        'Celtic' => array('celtic', false),
        'Gospel' => array('gospel', false),
        'Christian' => array('christian', true),
        'Worship' => array('worship', false),
        'Talk' => array('talk', true),
        'News' => array('news', true),
        'Public Radio' => array('public radio', false),
        'Sports' => array('sports', false),
        'Comedy' => array('comedy', false),
        'Kids' => array('kids', false),
        'Soundtracks' => array('soundtrack', false),
        'Holiday' => array('christmas', false),
        'Weather' => array('weather', false),
        'Scanner' => array('scanner', false),
        'Ham Radio' => array('amateur radio', false)
    );
}

function pico_fail($message) {
    http_response_code(503);
    header('Content-Type: text/plain; charset=us-ascii');
    header('Cache-Control: no-store');
    echo 'Directory unavailable: ', $message, "\n";
    exit;
}

function pico_ascii($value, $limit) {
    $value = (string)$value;
    if (function_exists('iconv')) {
        $converted = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $value);
        if ($converted !== false) $value = $converted;
    }
    $value = preg_replace('/[^\x20-\x7E]/', '', $value);
    $value = preg_replace('/\s+/', ' ', $value);
    return substr(trim($value), 0, $limit);
}

function pico_stream_url($value) {
    if (!is_string($value) || strlen($value) > 700 || preg_match('/[\x00-\x20\x7F]/', $value)) return null;
    $parts = @parse_url($value);
    if (!$parts || !in_array(strtolower($parts['scheme'] ?? ''), array('http', 'https'), true)) return null;
    if (empty($parts['host']) || isset($parts['user']) || isset($parts['pass'])) return null;
    $host = strtolower($parts['host']);
    if ($host === 'localhost' || substr($host, -6) === '.local' || strpos($host, ':') !== false) return null;
    if (filter_var($host, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
        if (!filter_var($host, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) return null;
    }
    // The original Revo Pico player cannot open modern HTTPS stream URLs.
    // Normalize the *playback URL* only; directory API requests stay HTTPS.
    // Normalizing before pool de-duplication also removes HTTP/HTTPS duplicates.
    // This does not make HTTPS-only origin servers support HTTP.
    return 'http://' . substr($value, strlen($parts['scheme']) + 3);
}

function pico_add_to_pool(&$pool, &$localSeen, $name, $url) {
    if (count($pool) >= PICO_MAX_GENRE_POOL) return;
    $name = pico_ascii($name, 100);
    $url = pico_stream_url($url);
    if ($name === '' || $url === null || isset($localSeen[$url])) return;
    $localSeen[$url] = true;
    $pool[] = array($name, $url);
}

function pico_http_get($url, $maxBytes) {
    $body = '';
    $ch = curl_init($url);
    if ($ch === false) return null;
    curl_setopt_array($ch, array(
        CURLOPT_FOLLOWLOCATION => false,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT => 16,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_USERAGENT => 'RevoPicoStationDirectory/' . PICO_FEED_VERSION . ' (preservation project)',
        CURLOPT_HTTPHEADER => array('Accept: application/json, application/xml, text/xml'),
        CURLOPT_WRITEFUNCTION => function ($handle, $piece) use (&$body, $maxBytes) {
            if (strlen($body) + strlen($piece) > $maxBytes) return 0;
            $body .= $piece;
            return strlen($piece);
        }
    ));
    $okay = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return ($okay !== false && $code === 200) ? $body : null;
}

/** Fetch batches in parallel (only 5 in flight) to avoid hitting PHP timeouts.
 * Uses one Radio Browser mirror first; retries only unsuccessful requests.
 */
function pico_radio_results($catalog, $country) {
    $all = array();
    $remaining = array_keys($catalog);
    $hosts = array('de1.api.radio-browser.info', 'de2.api.radio-browser.info', 'nl1.api.radio-browser.info');
    foreach ($hosts as $host) {
        if (!$remaining) break;
        $retry = array();
        foreach (array_chunk($remaining, 5) as $chunk) {
            $mh = curl_multi_init();
            $handles = array(); $buffers = array();
            foreach ($chunk as $label) {
                $tag = $catalog[$label][0];
                $params = array('tag' => $tag, 'hidebroken' => 'true', 'order' => 'clickcount',
                    'reverse' => 'true', 'limit' => 220, 'bitrateMax' => 128);
                if ($country !== 'ALL') $params['countrycode'] = $country;
                $url = 'https://' . $host . '/json/stations/search?' . http_build_query($params);
                $buffers[$label] = '';
                $h = curl_init($url);
                if ($h === false) { $retry[] = $label; continue; }
                curl_setopt_array($h, array(
                    CURLOPT_FOLLOWLOCATION => false,
                    CURLOPT_CONNECTTIMEOUT => 5,
                    CURLOPT_TIMEOUT => 14,
                    CURLOPT_SSL_VERIFYPEER => true,
                    CURLOPT_SSL_VERIFYHOST => 2,
                    CURLOPT_USERAGENT => 'RevoPicoStationDirectory/' . PICO_FEED_VERSION . ' (preservation project)',
                    CURLOPT_HTTPHEADER => array('Accept: application/json'),
                    CURLOPT_WRITEFUNCTION => function ($curl, $piece) use (&$buffers, $label) {
                        if (strlen($buffers[$label]) + strlen($piece) > 1800000) return 0;
                        $buffers[$label] .= $piece;
                        return strlen($piece);
                    }
                ));
                $handles[$label] = $h;
                curl_multi_add_handle($mh, $h);
            }
            $active = 0;
            if ($handles) {
                do {
                    do { $mc = curl_multi_exec($mh, $active); } while ($mc === CURLM_CALL_MULTI_PERFORM);
                    if ($mc !== CURLM_OK) break;
                    if ($active) {
                        $ready = curl_multi_select($mh, 1.0);
                        if ($ready === -1) usleep(100000);
                    }
                } while ($active);
            }
            foreach ($handles as $label => $h) {
                $valid = curl_errno($h) === 0 && (int)curl_getinfo($h, CURLINFO_HTTP_CODE) === 200;
                $rows = $valid ? json_decode($buffers[$label], true) : null;
                if (is_array($rows)) $all[$label] = $rows;
                else $retry[] = $label;
                curl_multi_remove_handle($mh, $h);
                curl_close($h);
            }
            curl_multi_close($mh);
        }
        $remaining = $retry;
    }
    return $all;
}

function pico_from_radio($catalog, $country) {
    $pools = array();
    foreach ($catalog as $label => $unused) $pools[$label] = array();
    $raw = pico_radio_results($catalog, $country);
    foreach ($catalog as $label => $unused) {
        $seen = array();
        foreach ($raw[$label] ?? array() as $row) {
            if (!is_array($row) || empty($row['lastcheckok'])) continue;
            $codec = strtoupper(trim((string)($row['codec'] ?? '')));
            if ($codec !== 'MP3' && $codec !== 'MPEG') continue;
            $rate = (int)($row['bitrate'] ?? 0);
            if ($rate > 128) continue;
            $url = ($row['url_resolved'] ?? '') ?: ($row['url'] ?? '');
            pico_add_to_pool($pools[$label], $seen, $row['name'] ?? '', $url);
        }
    }
    return $pools;
}

function pico_from_xiph($catalog) {
    $pools = array(); $seens = array();
    foreach ($catalog as $label => $unused) { $pools[$label] = array(); $seens[$label] = array(); }
    if (!class_exists('XMLReader') || !function_exists('simplexml_load_string')) return $pools;
    $xml = pico_http_get('https://dir.xiph.org/yp.xml', 20000000);
    if ($xml === null) return $pools;
    $reader = new XMLReader();
    if (!@$reader->XML($xml, null, LIBXML_NONET | LIBXML_NOERROR | LIBXML_NOWARNING)) return $pools;
    while (@$reader->read()) {
        if ($reader->nodeType !== XMLReader::ELEMENT || $reader->localName !== 'entry') continue;
        $entry = @simplexml_load_string($reader->readOuterXML(), 'SimpleXMLElement', LIBXML_NONET);
        if (!$entry) continue;
        $type = strtolower((string)$entry->server_type);
        if (strpos($type, 'mpeg') === false && strpos($type, 'mp3') === false) continue;
        $bitrate = (int)$entry->bitrate;
        if ($bitrate > 128) continue;
        $tags = strtolower((string)$entry->genre);
        foreach ($catalog as $label => $config) {
            if (strpos($tags, strtolower($config[0])) !== false) {
                pico_add_to_pool($pools[$label], $seens[$label], (string)$entry->server_name,
                    (string)$entry->listen_url);
                break;
            }
        }
    }
    $reader->close();
    return $pools;
}

/** Select a broad first pass, then add extra depth to popular genres.
 * Each group header/page is included in the byte accounting.
 */
function pico_assemble($pools, $catalog) {
    $selected = array(); $positions = array(); $seen = array();
    foreach ($catalog as $label => $config) { $selected[$label] = array(); $positions[$label] = 0; }
    $size = strlen("#EXTM3U\n"); $count = 0;
    // All categories get an initial allocation before big genres expand.
    foreach (array(15, 100, 55) as $pass => $quota) {
        foreach ($catalog as $label => $config) {
            if ($pass === 1 && !$config[1]) continue; // extra 100 for popular genres
            if ($pass === 2 && $config[1]) continue;  // extra 55 for other genres
            $pool = $pools[$label] ?? array();
            while (count($selected[$label]) < $quota && $positions[$label] < count($pool)) {
                $candidate = $pool[$positions[$label]++];
                $name = $candidate[0]; $url = $candidate[1];
                if (isset($seen[$url])) continue; // global de-duplication
                $n = count($selected[$label]);
                $extra = strlen('#EXTINF:' . $name . "\n" . $url . "\n");
                if ($n % PICO_STATIONS_PER_FOLDER === 0) {
                    $page = (int)floor($n / PICO_STATIONS_PER_FOLDER) + 1;
                    $folder = $label . ($page > 1 ? ' ' . $page : '');
                    $extra += strlen('#EXTGRP:' . $folder . "\n");
                }
                if ($size + $extra > PICO_MAX_BYTES || $count >= PICO_MAX_STATIONS) return pico_render($selected);
                $size += $extra; $count++;
                $seen[$url] = true;
                $selected[$label][] = array($name, $url);
            }
        }
    }
    return pico_render($selected);
}

function pico_render($selected) {
    $lines = array('#EXTM3U');
    foreach ($selected as $label => $stations) {
        foreach ($stations as $i => $station) {
            if ($i % PICO_STATIONS_PER_FOLDER === 0) {
                $part = (int)floor($i / PICO_STATIONS_PER_FOLDER) + 1;
                $folder = $label . ($part > 1 ? ' ' . $part : '');
                $lines[] = '#EXTGRP:' . $folder;
            }
            $lines[] = '#EXTINF:' . $station[0];
            $lines[] = $station[1];
        }
    }
    return implode("\n", $lines) . "\n";
}

// A local unit-test harness can include the functions without invoking HTTP.
if (defined('PICO_FEED_FUNCTIONS_ONLY')) return;
if (!function_exists('curl_init') || !function_exists('curl_multi_init')) pico_fail('PHP cURL extension required');
$source = isset($_GET['source']) ? strtolower((string)$_GET['source']) : 'radio';
if (!in_array($source, array('radio', 'xiph'), true)) pico_fail('source must be radio or xiph');
$country = isset($_GET['country']) ? strtoupper((string)$_GET['country']) : 'US';
if ($country !== 'ALL' && !preg_match('/^[A-Z]{2}$/D', $country)) pico_fail('invalid country');
$catalog = pico_genres();
$cacheKey = hash('sha256', PICO_FEED_VERSION . '|' . $source . '|' . $country . '|' . json_encode($catalog));
$cacheFile = sys_get_temp_dir() . '/revo_pico_feed_' . $cacheKey . '.m3u';
$cached = null;
if (is_file($cacheFile)) {
    $old = @file_get_contents($cacheFile);
    if ($old !== false && substr($old, 0, 7) === '#EXTM3U' && strlen($old) <= PICO_MAX_BYTES) $cached = $old;
}
if ($cached !== null && time() - @filemtime($cacheFile) < PICO_CACHE_SECONDS) {
    $feed = $cached;
} else {
    @set_time_limit(150);
    $pools = $source === 'xiph' ? pico_from_xiph($catalog) : pico_from_radio($catalog, $country);
    $feed = pico_assemble($pools, $catalog);
    if (strpos($feed, '#EXTINF:') === false) {
        if ($cached === null) pico_fail('no usable MP3 streams found');
        $feed = $cached; // keep a working old feed if the directory is temporarily down
    } else {
        @file_put_contents($cacheFile, $feed, LOCK_EX);
    }
}
header('Content-Type: audio/x-mpegurl; charset=us-ascii');
header('Cache-Control: public, max-age=3600');
header('Content-Length: ' . strlen($feed));
echo $feed;