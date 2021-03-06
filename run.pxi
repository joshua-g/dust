(require dust.project :as p)
(refer 'dust.project :only '(defproject load-project!))

(require dust.deps :as d)
(require pixie.string :as str)
(require pixie.io :as io)
(require pixie.fs :as fs)
(require pixie.test :as t)

(def *all-commands* (atom {}))

(defmacro defcmd
  [name description params & body]
  (let [body (if (:no-project (meta name))
               body
               (cons `(load-project!) body))
        cmd {:name (str name)
             :description description
             :params `(quote ~params)
             :cmd (cons `fn (cons params body))}]
    `(do (swap! *all-commands* assoc '~name ~cmd)
         '~name)))

(defcmd describe
  "Describe the current project."
  []
  (p/describe @p/*project*))

(defcmd deps
  "List the dependencies and their versions of the current project."
  []
  (doseq [[name version] (:dependencies @p/*project*)]
    (println name version)))

(defcmd load-path
  "Print the load path of the current project."
  []
  (when (not (fs/exists? (fs/file ".load-path")))
    (println "Please run `dust get-deps`")
    (exit 1))
  (doseq [path (str/split (io/slurp ".load-path") "--load-path")]
    (when (not (str/empty? path))
      (println (str/trim path)))))

(defcmd get-deps
  "Download the dependencies of the current project."
  []
  (-> @p/*project* d/get-deps d/write-load-path))

(defcmd ^:no-project repl
  "Start a REPL in the current project."
  []
  (throw (str "This should be invoked by the wrapper.")))

(defcmd ^:no-project run
  "Run the code in the given file."
  [file]
  (throw (str "This should be invoked by the wrapper.")))

(defn load-tests [dirs]
  (println "Looking for tests...")
  (let [dirs (distinct (map fs/dir dirs))
        pxi-files (->> dirs
                       (mapcat fs/walk-files)
                       (filter #(fs/extension? % "pxi"))
                       (filter #(str/starts-with? (fs/basename %) "test-"))
                       (distinct))]
    (foreach [file pxi-files]
             (println "Loading " file)
             (load-file (fs/abs file)))))

(defcmd test "Run the tests of the current project."
  [& args]
  (println @load-paths)

  (load-tests (:test-paths @p/*project*))

  (let [result (apply t/run-tests args)]
    (exit (get result :fail))))

(defn help-cmd [cmd]
  (let [{:keys [name description params] :as info} (get @*all-commands* (symbol cmd))]
    (if info
      (do
        (println (str "Usage: dust " name " " params))
        (println)
        (println description))
      (println "Unknown command:" cmd))))

(defn help-all []
  (println "Usage: dust <cmd> <options>")
  (println)
  (println "Available commands:")
  (doseq [{:keys [name description]} (vals @*all-commands*)]
    (println (str "  " name (apply str (repeat (- 10 (count name)) " ")) description))))

(defcmd ^:no-project help
  "Display the help"
  [& [cmd]]
  (if cmd
    (help-cmd cmd)
    (help-all)))

(def *command* (first program-arguments))

(let [cmd (get @*all-commands* (symbol *command*))]
  (try
    (if cmd
      (apply (get cmd :cmd) (next program-arguments))
      (println "Unknown command:" *command*))
    (catch :dust/Exception e
      (println (str "Dust encountered an error: " (pr-str (ex-msg e)))))))
