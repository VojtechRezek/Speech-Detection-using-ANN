function test_detect()
% TEST_DETECT - GUI pro detekci řečové aktivity pomocí ANN

clc; clear; close all;

% Vytvoření hlavního GUI okna
fig = figure('Name', 'Detektor řečové aktivity (VAD)', ...
             'NumberTitle', 'off', ...
             'Position', [100 100 900 600], ...
             'MenuBar', 'none', ...
             'ToolBar', 'none');

% UI komponenty
uicontrol('Style', 'text', ...
          'String', 'Vyberte zdroj audio signálu:', ...
          'Position', [50 520 300 30], ...
          'FontSize', 11, ...
          'HorizontalAlignment', 'left');

btn_record = uicontrol('Style', 'pushbutton', ...
                      'String', '🎤 Nahrát z mikrofonu', ...
                      'Position', [50 470 200 40], ...
                      'FontSize', 10, ...
                      'Callback', @record_audio);

btn_load = uicontrol('Style', 'pushbutton', ...
                    'String', '📂 Načíst soubor', ...
                    'Position', [50 420 200 40], ...
                    'FontSize', 10, ...
                    'Callback', @load_audio);

btn_train = uicontrol('Style', 'pushbutton', ...
                     'String', '🧠 Natrénovat ANN', ...
                     'Position', [50 370 200 40], ...
                     'FontSize', 10, ...
                     'Callback', @train_ann);

btn_load_model = uicontrol('Style', 'pushbutton', ...
                          'String', '💾 Načíst ANN model', ...
                          'Position', [50 320 200 40], ...
                          'FontSize', 10, ...
                          'Callback', @load_ann_model);

btn_play = uicontrol('Style', 'pushbutton', ...
                    'String', '▶ Přehrát', ...
                    'Position', [50 270 200 40], ...
                    'FontSize', 10, ...
                    'Enable', 'off', ...
                    'Callback', @play_audio);

btn_analyze = uicontrol('Style', 'pushbutton', ...
                       'String', '🔍 Analyzovat', ...
                       'Position', [50 220 200 40], ...
                       'FontSize', 10, ...
                       'Enable', 'off', ...
                       'Callback', @analyze_audio);

txt_status = uicontrol('Style', 'text', ...
                      'String', 'Stav: Čekám na vstup...', ...
                      'Position', [50 150 600 30], ...
                      'FontSize', 10, ...
                      'HorizontalAlignment', 'left');

% Panel pro výsledky
result_panel = uipanel('Title', 'Výsledky', ...
                      'Position', [0.35 0.1 0.6 0.8]);

% Proměnné pro data
audio_data = [];
fs = [];
player = [];
ann_model = [];

    % Funkce pro nahrávání z mikrofonu
    function record_audio(~, ~)
        set(txt_status, 'String', 'Připravuji nahrávání...');
        drawnow;
        
        try
            fs = 44100; % Standardní vzorkovací frekvence
            rec_obj = audiorecorder(fs, 16, 1);
            set(txt_status, 'String', 'Nahrávání - mluvte do mikrofonu... (klikněte pro stop)');
            drawnow;
            
            recordblocking(rec_obj, 5);
            stop(rec_obj);
            
            audio_data = getaudiodata(rec_obj);
            if isempty(audio_data)
                error('Žádná data nenahrána!');
            end
            fprintf('Nahráno: délka=%1.2f s, fs=%d Hz, rozměry=%s\n', ...
                    length(audio_data)/fs, fs, mat2str(size(audio_data)));
            set(txt_status, 'String', sprintf('Nahráno %1.2f sekund signálu (fs=%d Hz)', ...
                                             length(audio_data)/fs, fs));
            enable_controls(true);
        catch e
            set(txt_status, 'String', sprintf('Chyba při nahrávání: %s', e.message));
            enable_controls(false);
        end
    end

    % Funkce pro načtení souboru
    function load_audio(~, ~)
        [filename, pathname] = uigetfile({'*.wav;*.mp3;*.ogg;*.flac;*.m4a', ...
                                         'Audio Files (*.wav, *.mp3, *.ogg, *.flac, *.m4a)'}, ...
                                         'Vyberte audio soubor');
        if isequal(filename, 0)
            set(txt_status, 'String', 'Načítání zrušeno');
            enable_controls(false);
            return;
        end
        
        fullpath = fullfile(pathname, filename);
        set(txt_status, 'String', ['Načítám: ' filename '...']);
        drawnow;
        
        try
            [audio_data, fs] = audioread(fullpath);
            if size(audio_data,2) > 1
                audio_data = mean(audio_data, 2); % Převod na mono
            end
            max_duration = 30;
            if length(audio_data)/fs > max_duration
                audio_data = audio_data(1:max_duration*fs);
                set(txt_status, 'String', ...
                   sprintf('Načteno prvních %d sekund z %s (fs=%d Hz)', max_duration, filename, fs));
            else
                set(txt_status, 'String', ...
                   sprintf('Načten celý soubor %s (%1.2f sec, fs=%d Hz)', filename, length(audio_data)/fs, fs));
            end
            fprintf('Načteno: %s, délka=%1.2f s, fs=%d Hz, rozměry=%s\n', ...
                    filename, length(audio_data)/fs, fs, mat2str(size(audio_data)));
            enable_controls(true);
        catch e
            set(txt_status, 'String', sprintf('Chyba při načítání souboru: %s', e.message));
            enable_controls(false);
        end
    end

    % Funkce pro trénování ANN
    function train_ann(~, ~)
        set(txt_status, 'String', 'Vyberte složku s trénovacím datasetem...');
        drawnow;
        
        folder = uigetdir('', 'Vyberte složku s audio soubory a anotacemi');
        if isequal(folder, 0)
            set(txt_status, 'String', 'Výběr zrušen');
            return;
        end
        
        try
            % Rekurzivní načtení .wav a .TextGrid souborů
            set(txt_status, 'String', 'Načítám audio a TextGrid soubory...');
            drawnow;
            audio_files = get_files_recursive(folder, 'wav');
            textgrid_files = get_files_recursive(folder, 'TextGrid');
            
            % Ladící výpis
            fprintf('Nalezeno %d .wav souborů a %d .TextGrid souborů.\n', ...
                    length(audio_files), length(textgrid_files));
            set(txt_status, 'String', sprintf('Nalezeno %d .wav a %d .TextGrid souborů', ...
                                              length(audio_files), length(textgrid_files)));
            drawnow;
            
            if isempty(audio_files)
                set(txt_status, 'String', 'Chyba: Nenalezeny žádné .wav soubory!');
                return;
            end
            if isempty(textgrid_files)
                set(txt_status, 'String', 'Chyba: Nenalezeny žádné .TextGrid soubory!');
                return;
            end
            
            set(txt_status, 'String', 'Extrahuji příznaky a anotace z datasetu...');
            drawnow;
            
            % Extrakce příznaků a anotací
            features = [];
            labels = [];
            frame_shift = round(0.010 * 44100); % 10 ms
            skipped_files = 0;
            processed_files = 0;
            
            for i = 1:length(audio_files)
                audio_file = audio_files{i};
                [~, audio_name, ~] = fileparts(audio_file);
                fprintf('Zpracovávám soubor: %s\n', audio_file);
                
                try
                    % Načtení audio souboru
                    [audio, fs] = audioread(audio_file);
                    if size(audio,2) > 1
                        audio = mean(audio, 2);
                    end
                    
                    % Extrakce příznaků
                    [~, zcr, f0, energy, spectral_entropy] = simple_vad(audio, fs, []);
                    if isempty(zcr) || isempty(f0) || isempty(energy) || isempty(spectral_entropy)
                        warning('Prázdné příznaky pro %s, přeskakuji...', audio_name);
                        skipped_files = skipped_files + 1;
                        continue;
                    end
                    file_features = [zcr, energy, f0, spectral_entropy];
                    fprintf('Příznaky extrahovány pro %s: %d rámců\n', audio_name, length(zcr));
                    
                    % Najdeme odpovídající .TextGrid soubor
                    textgrid_file = '';
                    for j = 1:length(textgrid_files)
                        [~, tg_name, ~] = fileparts(textgrid_files{j});
                        if strcmpi(audio_name, tg_name)
                            textgrid_file = textgrid_files{j};
                            break;
                        end
                    end
                    
                    if isempty(textgrid_file)
                        warning('Nenalezen TextGrid pro %s, přeskakuji...', audio_name);
                        skipped_files = skipped_files + 1;
                        continue;
                    end
                    
                    % Načtení anotací z TextGrid
                    fprintf('Parsuji TextGrid: %s\n', textgrid_file);
                    annotations = parse_textgrid(textgrid_file);
                    if isempty(annotations)
                        warning('Žádné platné anotace v %s, přeskakuji...', textgrid_file);
                        skipped_files = skipped_files + 1;
                        continue;
                    end
                    
                    % Vytvoření štítků
                    file_labels = zeros(size(zcr));
                    for j = 1:size(annotations, 1)
                        start_frame = floor(annotations(j, 1) * fs / frame_shift) + 1;
                        end_frame = floor(annotations(j, 2) * fs / frame_shift) + 1;
                        if start_frame <= length(file_labels) && end_frame > 0
                            file_labels(start_frame:min(end_frame, length(file_labels))) = 1;
                        end
                    end
                    
                    % Kontrola, zda jsou štítky smysluplné
                    if sum(file_labels) == 0
                        warning('Žádné úseky řeči v anotacích pro %s, přeskakuji...', audio_name);
                        skipped_files = skipped_files + 1;
                        continue;
                    end
                    
                    % Kontrola platnosti příznaků
                    if any(isnan(file_features(:))) || any(isinf(file_features(:)))
                        warning('Neplatné hodnoty (NaN nebo Inf) v příznacích pro %s, přeskakuji...', audio_name);
                        skipped_files = skipped_files + 1;
                        continue;
                    end
                    
                    % Přidání dat do celkových matic
                    features = [features; file_features];
                    labels = [labels; file_labels];
                    processed_files = processed_files + 1;
                    fprintf('Úspěšně zpracován soubor: %s (%d anotací, %d rámců)\n', ...
                            audio_name, size(annotations, 1), length(zcr));
                    
                catch e
                    warning('Chyba při zpracování %s: %s', audio_name, e.message);
                    skipped_files = skipped_files + 1;
                    continue;
                end
            end
            
            % Shrnutí zpracování
            fprintf('Zpracováno %d souborů, přeskočeno %d souborů.\n', processed_files, skipped_files);
            set(txt_status, 'String', sprintf('Zpracováno %d souborů, přeskočeno %d souborů', ...
                                              processed_files, skipped_files));
            drawnow;
            
            if isempty(features)
                set(txt_status, 'String', 'Chyba: Žádná data nebyla zpracována! Zkontrolujte konzoli pro detaily.');
                return;
            end
            
            % Kontrola dat před trénováním
            fprintf('Kontroluji data před trénováním...\n');
            fprintf('Rozměry features: %s\n', mat2str(size(features)));
            fprintf('Rozměry labels: %s\n', mat2str(size(labels)));
            fprintf('Počet NaN v features: %d\n', sum(isnan(features(:))));
            fprintf('Počet Inf v features: %d\n', sum(isinf(features(:))));
            fprintf('Unikátní hodnoty v labels: %s\n', mat2str(unique(labels)));
            fprintf('Počet tříd - ticho (0): %d, řeč (1): %d\n', ...
                    sum(labels == 0), sum(labels == 1));
            
            if size(features, 1) ~= size(labels, 1)
                error('Neshoda v počtu řádků: features (%d) vs. labels (%d)', ...
                      size(features, 1), size(labels, 1));
            end
            if size(features, 2) ~= 4
                error('Neplatný počet příznaků: očekáváno 4, nalezeno %d', size(features, 2));
            end
            if any(isnan(features(:))) || any(isinf(features(:)))
                error('Features obsahují neplatné hodnoty (NaN nebo Inf)');
            end
            if ~all(ismember(unique(labels), [0, 1]))
                error('Labels obsahují neplatné hodnoty, očekávány pouze 0 a 1');
            end
            
            % Převod labels na numerický formát pro regresi
            labels = double(labels); % Zajistíme, že labels jsou typu double
            
            % Vytvoření a trénování ANN
            set(txt_status, 'String', 'Trénuji ANN model...');
            drawnow;
            
            layers = [
                featureInputLayer(4) % ZCR, energie, F0, spektrální entropie
                fullyConnectedLayer(64)
                batchNormalizationLayer
                reluLayer
                fullyConnectedLayer(32)
                batchNormalizationLayer
                reluLayer
                fullyConnectedLayer(1)
                regressionLayer % Pro binární klasifikaci s číselnými štítky [0,1]
            ];
            
            options = trainingOptions('adam', ...
                'MaxEpochs', 20, ...
                'MiniBatchSize', 128, ...
                'Verbose', 1, ...
                'Plots', 'training-progress', ...
                'LearnRateSchedule', 'piecewise', ...
                'LearnRateDropFactor', 0.1, ...
                'LearnRateDropPeriod', 10);
            
            try
                ann_model = trainNetwork(features, labels, layers, options);
            catch e
                set(txt_status, 'String', sprintf('Chyba při trénování ANN: %s', e.message));
                fprintf('Chyba při trénování: %s\n', e.message);
                return;
            end
            
            % Uložení modelu
            [file, path] = uiputfile('*.mat', 'Uložit ANN model');
            if ~isequal(file, 0)
                save(fullfile(path, file), 'ann_model');
                set(txt_status, 'String', 'Model úspěšně natrénován a uložen!');
            else
                set(txt_status, 'String', 'Model natrénován, ale neuložen.');
            end
        catch e
            set(txt_status, 'String', sprintf('Chyba při trénování: %s', e.message));
            fprintf('Chyba při trénování: %s\n', e.message);
        end
    end

    % Funkce pro načtení ANN modelu
    function load_ann_model(~, ~)
        [filename, pathname] = uigetfile('*.mat', 'Vyberte ANN model');
        if isequal(filename, 0)
            set(txt_status, 'String', 'Načítání modelu zrušeno');
            return;
        end
        
        try
            load(fullfile(pathname, filename), 'ann_model');
            set(txt_status, 'String', 'ANN model úspěšně načten!');
        catch e
            set(txt_status, 'String', sprintf('Chyba při načítání modelu: %s', e.message));
            ann_model = [];
        end
    end

    % Funkce pro přehrání audio
    function play_audio(~, ~)
        if isempty(audio_data)
            set(txt_status, 'String', 'Žádná data k přehrání!');
            return;
        end
        if isempty(fs) || fs <= 0
            set(txt_status, 'String', 'Chyba: Neplatná vzorkovací frekvence!');
            return;
        end
        
        try
            if ~isempty(player) && isplaying(player)
                stop(player);
            end
            play_data = audio_data / max(abs(audio_data)); % Normalizace amplitudy
            fprintf('Přehrávám: délka=%1.2f s, fs=%d Hz, rozměry=%s\n', ...
                    length(play_data)/fs, fs, mat2str(size(play_data)));
            player = audioplayer(play_data, fs);
            set(txt_status, 'String', sprintf('Přehrávám (fs=%d Hz)...', fs));
            play(player);
            t = timer('ExecutionMode', 'singleShot', ...
                     'StartDelay', length(play_data)/fs, ...
                     'TimerFcn', @(~,~) set(txt_status, 'String', 'Přehrávání dokončeno'));
            start(t);
        catch e
            set(txt_status, 'String', sprintf('Chyba při přehrávání: %s', e.message));
            fprintf('Chyba při přehrávání: %s\n', e.message);
        end
    end

    % Funkce pro analýzu
    function analyze_audio(~, ~)
        if isempty(audio_data)
            set(txt_status, 'String', 'Žádná data ke zpracování!');
            return;
        end
        if isempty(ann_model)
            set(txt_status, 'String', 'Není načten žádný ANN model!');
            return;
        end
        if isempty(fs) || fs <= 0
            set(txt_status, 'String', 'Chyba: Neplatná vzorkovací frekvence!');
            return;
        end
        
        set(txt_status, 'String', 'Zpracování...');
        drawnow;
        
        delete(get(result_panel, 'Children'));
        
        % Analýza pomocí ANN bez modifikace původních dat
        audio_data_norm = audio_data / max(abs(audio_data));
        fprintf('Analyzuji: délka=%1.2f s, fs=%d Hz, rozměry=%s\n', ...
                length(audio_data_norm)/fs, fs, mat2str(size(audio_data_norm)));
        [vad, zcr, f0, energy, spectral_entropy] = simple_vad(audio_data_norm, fs, ann_model);
        plot_results(audio_data_norm, fs, vad, zcr, f0, energy, spectral_entropy, 'VAD výsledky (ANN model)');
        
        set(txt_status, 'String', 'Analýza dokončena. Výsledky zobrazeny.');
    end

    % Pomocná funkce pro ovládací prvky
    function enable_controls(state)
        set(btn_play, 'Enable', ifelse(state, 'on', 'off'));
        set(btn_analyze, 'Enable', ifelse(state, 'on', 'off'));
    end

    % Pomocná funkce pro podmíněný výběr
    function out = ifelse(cond, a, b)
        if cond, out = a; else, out = b; end
    end

    % Funkce pro rekurzivní načtení souborů
    function files = get_files_recursive(root_dir, extension)
        files = {};
        fprintf('Prohledávám složku: %s\n', root_dir);
        dir_info = dir(root_dir);
        for k = 1:length(dir_info)
            if dir_info(k).isdir && ~strcmp(dir_info(k).name, '.') && ~strcmp(dir_info(k).name, '..')
                sub_files = get_files_recursive(fullfile(root_dir, dir_info(k).name), extension);
                files = [files, sub_files];
            elseif ~dir_info(k).isdir
                [~, ~, ext] = fileparts(dir_info(k).name);
                if strcmpi(ext(2:end), extension) % Ignorujeme tečku a porovnáváme bez ohledu na velikost písmen
                    full_path = fullfile(root_dir, dir_info(k).name);
                    files{end+1} = full_path;
                    fprintf('Nalezen soubor: %s\n', full_path);
                end
            end
        end
    end

    % Funkce pro parsování TextGrid souborů
    function annotations = parse_textgrid(filename)
        try
            fid = fopen(filename, 'r', 'n', 'UTF-8');
            if fid == -1
                error('Nelze otevřít TextGrid soubor: %s', filename);
            end
            text = fread(fid, '*char')';
            fclose(fid);
            
            % Parsování intervalů
            annotations = [];
            lines = splitlines(text);
            in_intervals = false;
            tier_name = '';
            
            for i = 1:length(lines)
                line = strtrim(lines{i});
                % Detekce názvu vrstvy
                if contains(line, 'name =')
                    tier_name = strtrim(extractAfter(line, 'name ='));
                    tier_name = tier_name(2:end-1); % Odstranění uvozovek
                end
                % Začátek intervalů
                if contains(line, 'intervals: size =')
                    in_intervals = true;
                    continue;
                end
                % Parsování intervalů
                if in_intervals && contains(line, 'xmin =')
                    xmin = str2double(strtrim(extractAfter(line, 'xmin =')));
                    next_line = strtrim(lines{i+1});
                    xmax = str2double(strtrim(extractAfter(next_line, 'xmax =')));
                    text_line = strtrim(lines{i+2});
                    text_val = strtrim(extractAfter(text_line, 'text ='));
                    text_val = text_val(2:end-1); % Odstranění uvozovek
                    % Přidání anotace, pokud je popisek "1" (řeč)
                    if strcmpi(text_val, '1')
                        annotations = [annotations; xmin, xmax];
                        fprintf('Nalezena anotace v %s: %.2f-%.2f, text="%s"\n', ...
                                filename, xmin, xmax, text_val);
                    end
                    i = i + 2; % Přeskočení dalších dvou řádků
                end
            end
            if isempty(annotations)
                warning('Žádné platné anotace (popisek "1") nalezeny v %s (vrstva: %s)', filename, tier_name);
            else
                fprintf('Nalezeno %d anotací v %s (vrstva: %s)\n', size(annotations, 1), filename, tier_name);
            end
        catch e
            warning('Chyba při parsování %s: %s', filename, e.message);
            annotations = [];
        end
    end

    % Funkce pro vykreslení výsledků
    function plot_results(signal, fs, vad, zcr, f0, energy, spectral_entropy, title_str)
        % Kontrola platnostimediaplayer signal, fs, vad, zcr, f0, energy, spectral_entropy, title_str
        % Kontrola platnosti vstupů
        if isempty(zcr) || isempty(vad) || isempty(f0) || isempty(energy) || isempty(spectral_entropy)
            error('Některý z příznaků je prázdný!');
        end
        
        ax1 = subplot(3,1,1, 'Parent', result_panel);
        plot(ax1, (1:length(signal))/fs, signal);
        hold(ax1, 'on');
        time_axis = (1:length(vad)) * 0.01;
        plot(ax1, time_axis, vad * 0.9 * max(signal), 'r', 'LineWidth', 1.5);
        title(ax1, title_str);
        xlabel(ax1, 'Čas (s)'); ylabel(ax1, 'Amplituda');
        legend(ax1, 'Signál', 'VAD rozhodnutí', 'Location', 'best');
        grid(ax1, 'on');
        
        ax2 = subplot(3,1,2, 'Parent', result_panel);
        time_axis = (1:length(zcr)) * 0.01;
        plot(ax2, time_axis, zcr, 'g');
        hold(ax2, 'on');
        plot(ax2, time_axis, f0, 'b');
        plot(ax2, time_axis, energy, 'm');
        plot(ax2, time_axis, spectral_entropy, 'k');
        xlabel(ax2, 'Čas (s)'); ylabel(ax2, 'Normalizované hodnoty');
        title(ax2, 'Extrahované příznaky');
        legend(ax2, 'ZCR', 'F0', 'Energie', 'Spektrální entropie', 'Location', 'best');
        grid(ax2, 'on');
        
        ax3 = subplot(3,1,3, 'Parent', result_panel);
        plot(ax3, time_axis, vad, 'r', 'LineWidth', 1.5);
        title(ax3, 'VAD rozhodnutí'); xlabel(ax3, 'Čas (s)'); ylabel(ax3, 'Rozhodnutí (0/1)');
        grid(ax3, 'on');
    end
end