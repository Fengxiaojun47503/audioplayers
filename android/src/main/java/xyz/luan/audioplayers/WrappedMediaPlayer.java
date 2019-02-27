package xyz.luan.audioplayers;

import android.annotation.TargetApi;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.text.TextUtils;

import java.io.IOException;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

public class WrappedMediaPlayer implements MediaPlayer.OnPreparedListener,
                                           MediaPlayer.OnCompletionListener,
                                           MediaPlayer.OnSeekCompleteListener {
    private final static String TAG = WrappedMediaPlayer.class.getSimpleName();

    public final static String AUDIO_SERVICE_ACTION = "xyz.luan.audioplayers.action.START_SERVICE";
    public final static String EXTRA_PLAYER_ID = "xyz.luan.audioplayers.extra.PLAYER_ID";
    public final static String EXTRA_COMMAND = "xyz.luan.audioplayers.extra.COMMAND";

    private String playerId;

    private String url;
    private double volume = 1.0;
    private ReleaseMode releaseMode = ReleaseMode.RELEASE;

    private boolean released = true;
    private boolean prepared = false;
    private boolean playing = false;

    private double shouldSeekTo = -1;
    private float speed= -1;
    private float currentSpeed= -1;

    private MediaPlayer player;
    private WeakHashMap<AudioView, Boolean> audioViews = new WeakHashMap<>(2);

    private static final Handler sHandler = new Handler();
    private static Runnable sPositionUpdates;
    private static final Object sLock = new Object();

    private static final Map<String, WrappedMediaPlayer> sMediaPlayers = new HashMap<>();

    public static WrappedMediaPlayer get(String playerId, AudioView audioView) {
        WrappedMediaPlayer player;
        synchronized (sLock) {
            player = sMediaPlayers.get(playerId);
            if (null == player) {
                player = new WrappedMediaPlayer(audioView, playerId);
                sMediaPlayers.put(playerId, player);
            } else {
                player.audioViews.put(audioView, Boolean.TRUE);
                if (!TextUtils.isEmpty(player.url)) {
                    audioView.onSourceSet(player, player.url);
                }
                if (player.isActuallyPlaying()) {
                    audioView.onStart(player);
                }
            }
        }
        return player;
    }

    public static void destroy(String playerId, AudioView audioView) {
        WrappedMediaPlayer player;
        synchronized (sLock) {
            if ((player = sMediaPlayers.get(playerId)) != null) {
                player.audioViews.remove(audioView);
                if (player.audioViews.isEmpty()) {
                    sMediaPlayers.remove(playerId);
                }
            }
        }
    }

    private static void startPositionUpdates() {
        if (sPositionUpdates == null) {
            sPositionUpdates = new UpdateCallback();
            sHandler.post(sPositionUpdates);
        }
    }

    private static void stopPositionUpdates() {
        sPositionUpdates = null;
        sHandler.removeCallbacksAndMessages(null);
    }

    private static final class UpdateCallback implements Runnable {
        @Override
        public void run() {
            if (sMediaPlayers.isEmpty()) {
                stopPositionUpdates();
                return;
            }

            boolean nonePlaying = true;
            for (WrappedMediaPlayer player : sMediaPlayers.values()) {
                if (!player.isActuallyPlaying()) {
                    continue;
                }
                nonePlaying = false;

                Set<AudioView> views;
                synchronized (sLock) {
                    views = new HashSet<>(player.audioViews.keySet());
                }

                if (!views.isEmpty()) {
                    final int duration = player.getDuration();
                    final int time = player.getCurrentPosition();
                    for (AudioView view : views) {
                        if (null != view) {
                            view.onProgressUpdate(player, duration, time);
                        }
                    }
                }
            }

            if (nonePlaying) {
                stopPositionUpdates();
            } else {
                sHandler.postDelayed(this, 200);
            }
        }
    }

    private WrappedMediaPlayer(AudioView ref, String playerId) {
        this.audioViews.put(ref, Boolean.TRUE);
        this.playerId = playerId;
    }

    public int getAudioViewCount() {
        return audioViews.size();
    }

    public void setUrl(String url) {
        if (!objectEquals(this.url, url)) {
            // save current play speed in order to play new url with same speed
            speed = currentSpeed;
            this.url = url;

            if (this.released) {
                this.player = createPlayer();
                this.released = false;
            } else if (this.prepared) {
                this.player.reset();
                this.prepared = false;
            }

            this.setSource(url);
            this.player.setVolume((float) volume, (float) volume);
            this.player.setLooping(this.releaseMode == ReleaseMode.LOOP);
            this.player.prepareAsync();

            Set<AudioView> views;
            synchronized (sLock) {
                views = new HashSet<>(audioViews.keySet());
            }

            if (!views.isEmpty()) {
                for (AudioView view : views) {
                    if (null != view) {
                        view.onSourceSet(this, url);
                    }
                }
            }
        }
    }

    public String getUrl() {
        return this.url;
    }

    public void setVolume(double volume) {
        if (this.volume != volume) {
            this.volume = volume;
            if (!this.released) {
                this.player.setVolume((float) volume, (float) volume);
            }
        }
    }

    public double getVolume() {
        return this.volume;
    }

    public boolean isPlaying() {
        return this.playing;
    }

    public boolean isActuallyPlaying() {
        return this.playing && this.prepared;
    }

    public void play() {
        if (!this.playing) {
            this.playing = true;
            if (this.released) {
                this.released = false;
                this.player = createPlayer();
                this.setSource(url);
                this.player.prepareAsync();
            } else if (this.prepared) {
                this.player.start();

                Set<AudioView> views;
                synchronized (sLock) {
                    views = new HashSet<>(audioViews.keySet());
                }

                if (!views.isEmpty()) {
                    for (AudioView view : views) {
                        if (null != view) {
                            view.onStart(this);
                        }
                    }
                    startPositionUpdates();
                }
            }
        }
    }

    public void stop() {
        if (this.released) {
            return;
        }

        if (releaseMode != ReleaseMode.RELEASE) {
            if (this.playing) {
                this.playing = false;
                this.player.pause();
                this.player.seekTo(0);
            }
        } else {
            this.release();
        }

        Set<AudioView> views;
        synchronized (sLock) {
            views = new HashSet<>(audioViews.keySet());
        }

        if (!views.isEmpty()) {
            for (AudioView view : views) {
                if (null != view) {
                    view.onStop(this);
                }
            }
        }
    }

    public void release() {
        if (this.released) {
            return;
        }

        if (this.playing) {
            this.player.stop();

            Set<AudioView> views;
            synchronized (sLock) {
                views = new HashSet<>(audioViews.keySet());
            }

            if (!views.isEmpty()) {
                for (AudioView view : views) {
                    if (null != view) {
                        view.onStop(this);
                    }
                }
            }
        }
        this.player.reset();
        this.player.release();
        this.player = null;

        this.prepared = false;
        this.released = true;
        this.playing = false;
    }

    public void pause() {
        if (this.playing) {
            this.playing = false;
            this.player.pause();

            Set<AudioView> views;
            synchronized (sLock) {
                views = new HashSet<>(audioViews.keySet());
            }

            if (!views.isEmpty()) {
                for (AudioView view : views) {
                    if (null != view) {
                        view.onPause(this);
                    }
                }
            }
        }
    }

    private void setSource(String url) {
        try {
            this.player.setDataSource(url);
        } catch (IOException ex) {
            throw new RuntimeException("Unable to access resource", ex);
        }
    }

    // seek operations cannot be called until after
    // the player is ready.
    public void seek(double position) {
        if (this.prepared) {
            this.player.seekTo((int) (position * 1000));
        } else {
            this.shouldSeekTo = position;
        }
    }

    public int getDuration() {
        return this.player.getDuration();
    }

    public int getCurrentPosition() {
        return this.player.getCurrentPosition();
    }

    public String getPlayerId() {
        return this.playerId;
    }

    public void setReleaseMode(ReleaseMode releaseMode) {
        if (this.releaseMode != releaseMode) {
            this.releaseMode = releaseMode;
            if (!this.released) {
                this.player.setLooping(releaseMode == ReleaseMode.LOOP);
            }
        }
    }

    public ReleaseMode getReleaseMode() {
        return this.releaseMode;
    }

    @TargetApi(23)
    public void setSpeed(float speed) {
        currentSpeed = speed;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if(prepared){
                player.setPlaybackParams(player.getPlaybackParams().setSpeed(speed));
                this.speed = -1;
            } else {
                this.speed = speed;
            }
        }
    }

    @Override
    public void onPrepared(final MediaPlayer mediaPlayer) {
        this.prepared = true;
        if (this.playing) {
            this.player.start();

            Set<AudioView> views;
            synchronized (sLock) {
                views = new HashSet<>(audioViews.keySet());
            }

            if (!views.isEmpty()) {
                for (AudioView view : views) {
                    if (null != view) {
                        view.onStart(this);
                    }
                }
                startPositionUpdates();
            }
        }
        if (this.shouldSeekTo >= 0) {
            this.player.seekTo((int) (this.shouldSeekTo * 1000));
            this.shouldSeekTo = -1;
        }
        if(this.speed > 0){
            setSpeed(this.speed);
        }
    }

    @Override
    public void onSeekComplete(MediaPlayer mp) {
        Set<AudioView> views;
        synchronized (sLock) {
            views = new HashSet<>(audioViews.keySet());
        }
        if (!views.isEmpty()) {
            for (AudioView view : views) {
                if (null != view) {
                    view.onSeekComplete(this);
                }
            }
        }
    }

    @Override
    public void onCompletion(final MediaPlayer mediaPlayer) {
        if (releaseMode != ReleaseMode.LOOP) {
            this.stop();
        }

        Set<AudioView> views;
        synchronized (sLock) {
            views = new HashSet<>(audioViews.keySet());
        }
        if (!views.isEmpty()) {
            for (AudioView view : views) {
                if (null != view) {
                    view.onComplete(this);
                }
            }
        }
    }

    @SuppressWarnings("deprecation")
    private void setAttributes(MediaPlayer player) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            player.setAudioAttributes(new AudioAttributes.Builder()
                                              .setUsage(AudioAttributes.USAGE_MEDIA)
                                              .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                              .build());
        } else {
            // This method is deprecated but must be used on older devices
            player.setAudioStreamType(AudioManager.STREAM_MUSIC);
        }
    }

    private MediaPlayer createPlayer() {
        MediaPlayer player = new MediaPlayer();
        player.setOnPreparedListener(this);
        player.setOnCompletionListener(this);
        player.setOnSeekCompleteListener(this);
        setAttributes(player);
        player.setVolume((float) volume, (float) volume);
        player.setLooping(this.releaseMode == ReleaseMode.LOOP);
        return player;
    }

    private static boolean objectEquals(Object o1, Object o2) {
        return o1 == null && o2 == null || o1 != null && o1.equals(o2);
    }
}
