function [vad_decision, zcr, f0, energy, spectral_entropy] = simple_vad(signal, fs, ann_model)
    % SIMPLE_VAD - Detektor řečové aktivity pomocí ANN
    % [vad_decision, zcr, f0, energy, spectral_entropy] = simple_vad(signal, fs, ann_model)
    %
    % Pokud ann_model není poskytnut nebo je prázdný, vrací pouze příznaky bez predikce.

    % Normalizace signálu
    signal = signal / max(abs(signal));
    
    % Parametry segmentace
    frame_length = round(0.025 * fs); % 25 ms
    frame_shift = round(0.010 * fs);  % 10 ms
    window = hamming(frame_length);
    
    % Počet rámců
    num_frames = floor((length(signal) - frame_length) / frame_shift) + 1;
    
    % Inicializace proměnných
    zcr = zeros(num_frames, 1);
    f0 = zeros(num_frames, 1);
    energy = zeros(num_frames, 1);
    spectral_entropy = zeros(num_frames, 1);
    vad_decision = zeros(num_frames, 1); % Výchozí hodnota, pokud není predikce
    
    % Výpočet příznaků pro každý rámec
    for i = 1:num_frames
        start_idx = (i-1)*frame_shift + 1;
        end_idx = min(start_idx + frame_length - 1, length(signal));
        
        frame = signal(start_idx:end_idx);
        if length(frame) < frame_length
            frame = [frame; zeros(frame_length-length(frame), 1)];
        end
        frame = frame .* window;
        
        % ZCR
        zcr(i) = sum(abs(diff(frame > 0))) / (2*frame_length);
        
        % Energie
        energy(i) = log(sum(frame.^2) + eps);
        
        % F0
        f0(i) = improved_f0_estimate(frame, fs);
        
        % Spektrální entropie
        N = length(frame);
        fft_frame = abs(fft(frame, N));
        fft_frame = fft_frame(1:floor(N/2));
        fft_frame = fft_frame / (sum(fft_frame) + eps);
        spectral_entropy(i) = -sum(fft_frame .* log2(fft_frame + eps));
    end
    
    % Normalizace příznaků
    zcr = (zcr - min(zcr)) / (max(zcr) - min(zcr) + eps);
    energy = (energy - min(energy)) / (max(energy) - min(energy) + eps);
    spectral_entropy = (spectral_entropy - min(spectral_entropy)) / ...
                       (max(spectral_entropy) - min(spectral_entropy) + eps);
    f0_valid = f0(f0 > 0);
    if ~isempty(f0_valid)
        f0(f0 > 0) = (f0_valid - min(f0_valid)) / (max(f0_valid) - min(f0_valid) + eps);
    end
    
    % Predikce pomocí ANN modelu, pokud je poskytnut
    if nargin >= 3 && ~isempty(ann_model)
        features = [zcr, energy, f0, spectral_entropy]';
        vad_decision = predict(ann_model, features') > 0.5; % Binární rozhodnutí
    end
end

function f0 = improved_f0_estimate(frame, fs)
    % Pre-emfáze
    pre_emph = [1 -0.97];
    frame = filter(pre_emph, 1, frame - mean(frame));
    
    % Centrální ořezávání
    clip_level = 0.3 * max(abs(frame));
    frame_clipped = frame;
    frame_clipped(abs(frame) < clip_level) = 0;
    
    % Autokorelace
    autocorr = xcorr(frame_clipped, 'coeff');
    autocorr = autocorr(length(frame_clipped):end);
    
    % Rozsah F0 (80-400 Hz)
    min_lag = round(fs/400);
    max_lag = round(fs/80);
    if max_lag > length(autocorr)
        f0 = 0;
        return;
    end
    autocorr = autocorr(min_lag:max_lag);
    
    % Hledání peaků
    [peaks, locs] = findpeaks(autocorr, 'MinPeakHeight', 0.4, ...
                              'MinPeakDistance', round(fs/400));
    
    if length(locs) >= 2
        f0 = fs / (locs(2) + min_lag - 1);
    elseif ~isempty(locs)
        f0 = fs / (2*(locs(1) + min_lag - 1));
    else
        f0 = 0;
    end
    
    if f0 < 80 || f0 > 400
        f0 = 0;
    end
end