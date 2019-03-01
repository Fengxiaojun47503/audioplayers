package xyz.luan.audioplayers;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.text.TextUtils;
import android.util.Log;

import java.util.HashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.PluginRegistry.Registrar;

import static xyz.luan.audioplayers.WrappedMediaPlayer.AUDIO_SERVICE_ACTION;
import static xyz.luan.audioplayers.WrappedMediaPlayer.EXTRA_PLAYER_ID;

public class AudioplayersPlugin implements MethodCallHandler, AudioView {
    private static final Logger LOGGER =
            Logger.getLogger(AudioplayersPlugin.class.getCanonicalName());
    private static final int STATE_PAUSE = -1;
    private static final int STATE_PLAY = -2;
    private static final int STATE_STOP = -3;

    private final MethodChannel channel;
    private final Context context;

    public static void registerWith(final Registrar registrar) {
        final MethodChannel channel =
                new MethodChannel(registrar.messenger(), "xyz.luan/audioplayers");
        channel.setMethodCallHandler(new AudioplayersPlugin(registrar.activeContext(), channel));
    }

    private AudioplayersPlugin(final Context context, final MethodChannel channel) {
        this.context = context.getApplicationContext();
        this.channel = channel;
        this.channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(final MethodCall call, final MethodChannel.Result response) {
        try {
            handleMethodCall(call, response);
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Unexpected error!", e);
            response.error("Unexpected error!", e.getMessage(), e);
        }
    }

    private void handleMethodCall(final MethodCall call, final MethodChannel.Result response) {
        switch (call.method) {
            case "fetchExistPlayer":
                String existPlayId = null;
                for (Map.Entry<String, WrappedMediaPlayer> entry :
                        WrappedMediaPlayer.sMediaPlayers.entrySet()) {
                    existPlayId = entry.getKey();

                    final WrappedMediaPlayer player = WrappedMediaPlayer.get(existPlayId, this);
                    if (player.isPlaying()) {
                        new Handler().postDelayed(new Runnable() {
                            @Override
                            public void run() {
                                channel.invokeMethod("audio.onDuration",
                                        buildArguments(player.getPlayerId(), STATE_PLAY));
                            }
                        }, 300);
                    }
                    break;
                }
                response.success(existPlayId);
                return;
            case "isSupportChangeSpeed":
                response.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                        && !TextUtils.equals(Build.VERSION.RELEASE, "6.0.1"));
                return;
            default:
                break;
        }
        final String playerId = call.argument("playerId");
        final WrappedMediaPlayer player = WrappedMediaPlayer.get(playerId, this);
        switch (call.method) {
            case "play": {
                final String url = call.argument("url");
                final double volume = call.argument("volume");
                final Double position = call.argument("position");
                player.setUrl(url);
                player.setVolume(volume);
                if (position != null) {
                    player.seek(position);
                }
                player.play();
                break;
            }
            case "resume": {
                player.play();
                break;
            }
            case "pause": {
                player.pause();
                break;
            }
            case "stop": {
                player.stop();
                break;
            }
            case "release": {
                player.release();
                break;
            }
            case "seek": {
                final Double position = call.argument("position");
                player.seek(position);
                break;
            }
            case "setVolume": {
                final double volume = call.argument("volume");
                player.setVolume(volume);
                break;
            }
            case "setUrl": {
                final String url = call.argument("url");
                player.setUrl(url);
                break;
            }
            case "setReleaseMode": {
                final String releaseModeName = call.argument("releaseMode");
                final ReleaseMode releaseMode =
                        ReleaseMode.valueOf(releaseModeName.substring("ReleaseMode.".length()));
                player.setReleaseMode(releaseMode);
                break;
            }
            case "setSpeed": {
                final float speed = ((Double) (call.argument("speed"))).floatValue();
                player.setSpeed(speed);
                break;
            }
            default: {
                response.notImplemented();
                return;
            }
        }
        response.success(1);
    }

    @Override
    public Context getApplicationContext() {
        return context;
    }

    @Override
    public void onStart(WrappedMediaPlayer player) {
        channel.invokeMethod("audio.onDuration", buildArguments(player.getPlayerId(), STATE_PLAY));
        Context context = getApplicationContext();
        Intent intent = new Intent(AUDIO_SERVICE_ACTION)
                                .setPackage(context.getPackageName())
                                .putExtra(EXTRA_PLAYER_ID, player.getPlayerId());
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    @Override
    public void onPause(WrappedMediaPlayer player) {
        channel.invokeMethod("audio.onDuration", buildArguments(player.getPlayerId(), STATE_PAUSE));
    }

    @Override
    public void onStop(WrappedMediaPlayer player) {
        channel.invokeMethod("audio.onDuration", buildArguments(player.getPlayerId(), STATE_STOP));
    }

    @Override
    public void onSourceSet(WrappedMediaPlayer player, String source) {}

    @Override
    public void onProgressUpdate(WrappedMediaPlayer player, int duration, int position) {
        channel.invokeMethod("audio.onDuration", buildArguments(player.getPlayerId(), duration));
        channel.invokeMethod(
                "audio.onCurrentPosition", buildArguments(player.getPlayerId(), position));
    }

    @Override
    public void onComplete(WrappedMediaPlayer player) {
        channel.invokeMethod("audio.onComplete", buildArguments(player.getPlayerId(), true));
    }

    @Override
    public void onSeekComplete(WrappedMediaPlayer player) {
        channel.invokeMethod("audio.onSeekComplete",
                buildArguments(player.getPlayerId(), player.getCurrentPosition()));
    }

    private static Map<String, Object> buildArguments(String playerId, Object value) {
        Map<String, Object> result = new HashMap<>(2);
        result.put("playerId", playerId);
        result.put("value", value);
        return result;
    }
}
