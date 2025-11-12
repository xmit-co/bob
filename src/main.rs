// ============================================================================
// Imports
// ============================================================================

use iced::widget::{button, column, container, mouse_area, row, scrollable, text, Space};
use iced::{Color, Element, Font, Length, Subscription};
use iced::Task as IcedTask;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::{mpsc, Mutex};
use std::collections::HashMap;
use notify_debouncer_full::{new_debouncer, notify::*, DebounceEventResult};
use std::time::Duration;

// ============================================================================
// Constants - Icons
// ============================================================================

const BOOTSTRAP_FONT: Font = Font::with_name("bootstrap-icons");
const BOOTSTRAP_FONT_BYTES: &[u8] = include_bytes!("../assets/bootstrap-icons.woff2");

const ICON_PLUS: &str = "\u{F64D}";   // Bootstrap Icons: plus-lg
const ICON_FOLDER: &str = "\u{F3EB}"; // Bootstrap Icons: folder-plus
const ICON_PLAY: &str = "\u{F4F4}";   // Bootstrap Icons: play-fill
const ICON_PAUSE: &str = "\u{F4C2}";  // Bootstrap Icons: pause-fill
const ICON_TRASH: &str = "\u{F5DE}";  // Bootstrap Icons: trash-fill

// ============================================================================
// Constants - High-Contrast Color Scheme
// ============================================================================

const BG_PRIMARY: Color = Color::BLACK;
const BG_SECONDARY: Color = Color::from_rgb(0.1, 0.1, 0.1);
const BG_HOVER: Color = Color::from_rgb(0.15, 0.15, 0.15);
const BG_SELECTED: Color = Color::from_rgb(0.0, 0.3, 0.6);
const BG_DRAGGING: Color = Color::from_rgb(0.2, 0.2, 0.2);

const TEXT_PRIMARY: Color = Color::WHITE;
const TEXT_ERROR: Color = Color::from_rgb(1.0, 0.3, 0.3);

const BORDER_COLOR: Color = Color::from_rgb(0.3, 0.3, 0.3);

// ============================================================================
// Constants - Bun Configuration
// ============================================================================

#[cfg(all(target_os = "windows", target_arch = "x86_64"))]
const BUN_DOWNLOAD_URL: &str = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.2/bun-windows-x64.zip";

#[cfg(all(target_os = "windows", target_arch = "aarch64"))]
const BUN_DOWNLOAD_URL: &str = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.2/bun-windows-aarch64.zip";

#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
const BUN_DOWNLOAD_URL: &str = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.2/bun-darwin-x64.zip";

#[cfg(all(target_os = "macos", target_arch = "aarch64"))]
const BUN_DOWNLOAD_URL: &str = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.2/bun-darwin-aarch64.zip";

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
const BUN_DOWNLOAD_URL: &str = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.2/bun-linux-x64.zip";

#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
const BUN_DOWNLOAD_URL: &str = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.2/bun-linux-aarch64.zip";

// ============================================================================
// Main Entry Point
// ============================================================================

fn main() -> iced::Result {
    iced::application("Project Manager", App::update, App::view)
        .subscription(App::subscription)
        .font(BOOTSTRAP_FONT_BYTES)
        .run()
}

// ============================================================================
// Message Types
// ============================================================================

/// Application messages for user interactions
#[derive(Debug, Clone)]
enum Message {
    // Project management
    ImportProject,
    ImportProjectSelected(Option<PathBuf>),
    CreateProject,
    RemoveProject(usize),

    // Task interactions
    SelectTask(usize, usize),
    StartTask(usize, usize),
    StopTask(usize, usize),
    TaskOutput(usize, usize, String),
    TaskCompleted(usize, usize, bool, Vec<String>),

    // Drag-and-drop
    ProjectDragStart(usize),
    ProjectDragEnd,
    ProjectHovered(usize),

    // Panel resizing
    DividerDragStart,
    DividerDragging(f32),
    DividerDragEnd,

    // Bun management
    BunDownloadProgress(f32),
    BunReady,

    // File watching
    FileChanged(PathBuf),
    RefreshProjects,
}

// ============================================================================
// Data Structures
// ============================================================================

/// A single task within a project
#[derive(Clone, Serialize, Deserialize)]
struct ProjectTask {
    name: String,
    #[serde(skip)]
    running: bool,
    #[serde(skip)]
    logs: Vec<String>,
    #[serde(default)]
    failed: bool,
}

/// A project containing multiple tasks
#[derive(Clone, Serialize, Deserialize)]
struct Project {
    name: String,
    path: String,
    tasks: Vec<ProjectTask>,
    #[serde(skip)]
    hidden: bool,
}

/// Persistent configuration
#[derive(Serialize, Deserialize, Default)]
struct Config {
    projects: Vec<Project>,
}

/// Process handle for running tasks
struct ProcessHandle {
    child: Arc<Mutex<Child>>,
    _output_task: tokio::task::JoinHandle<()>,
}

/// Main application state
struct App {
    projects: Vec<Project>,
    selected_task: Option<(usize, usize)>,
    dragging_project: Option<usize>,
    processes: HashMap<(usize, usize), ProcessHandle>,
    bun_path: Option<PathBuf>,
    bun_downloading: bool,
    left_panel_width: f32,
    dragging_divider: bool,
}

// ============================================================================
// File Watching Subscription
// ============================================================================

enum FileWatcherState {
    Starting,
    Ready(mpsc::UnboundedReceiver<PathBuf>),
}

async fn watch_projects(projects: Vec<String>) -> mpsc::UnboundedReceiver<PathBuf> {
    let (tx, rx) = mpsc::unbounded_channel();

    tokio::task::spawn_blocking(move || {
        let tx_clone = tx.clone();

        let mut debouncer = new_debouncer(
            Duration::from_millis(500),
            None,
            move |result: DebounceEventResult| {
                match result {
                    Ok(events) => {
                        for event in events {
                            for path in &event.paths {
                                if path.file_name().and_then(|n| n.to_str()) == Some("package.json") {
                                    let _ = tx_clone.send(path.clone());
                                }
                            }
                        }
                    }
                    Err(e) => eprintln!("File watcher error: {:?}", e),
                }
            },
        ).expect("Failed to create file watcher");

        for project_path in projects {
            let path = PathBuf::from(project_path);
            if path.exists() {
                let _ = debouncer.watch(&path, RecursiveMode::NonRecursive);
            }
        }

        // Keep the debouncer alive
        std::thread::park();
    });

    rx
}

fn file_watcher_subscription(projects: Vec<Project>) -> Subscription<Message> {
    struct FileWatcher;

    Subscription::run_with_id(
        std::any::TypeId::of::<FileWatcher>(),
        futures::stream::unfold(FileWatcherState::Starting, move |mut state| {
            let projects = projects.clone();
            async move {
                match &mut state {
                    FileWatcherState::Starting => {
                        let project_paths: Vec<String> = projects
                            .iter()
                            .map(|p| p.path.clone())
                            .filter(|p| !p.is_empty())
                            .collect();

                        if !project_paths.is_empty() {
                            let rx = watch_projects(project_paths).await;
                            state = FileWatcherState::Ready(rx);
                        } else {
                            tokio::time::sleep(Duration::from_secs(5)).await;
                        }
                        Some((Message::RefreshProjects, state))
                    }
                    FileWatcherState::Ready(rx) => {
                        if let Some(path) = rx.recv().await {
                            Some((Message::FileChanged(path), state))
                        } else {
                            None
                        }
                    }
                }
            }
        })
    )
}

// ============================================================================
// Application Implementation
// ============================================================================

impl Default for App {
    fn default() -> Self {
        let config: Config = confy::load("bob", "config").unwrap_or_default();
        let mut projects = config.projects;

        // Check which projects exist
        for project in &mut projects {
            let package_json = Path::new(&project.path).join("package.json");
            project.hidden = !package_json.exists();
        }

        let bun_path = Self::get_bun_path();

        Self {
            projects,
            selected_task: None,
            dragging_project: None,
            processes: HashMap::new(),
            bun_path,
            bun_downloading: false,
            left_panel_width: 300.0,
            dragging_divider: false,
        }
    }
}

impl App {
    // ------------------------------------------------------------------------
    // Bun Management
    // ------------------------------------------------------------------------

    /// Gets the path to the cached bun executable
    fn get_bun_path() -> Option<PathBuf> {
        let cache_dir = dirs::cache_dir()?.join("bob");
        let bun_name = if cfg!(windows) { "bun.exe" } else { "bun" };
        let bun_path = cache_dir.join(bun_name);

        if bun_path.exists() {
            Some(bun_path)
        } else {
            None
        }
    }

    /// Downloads and installs bun
    async fn download_bun() -> std::result::Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
        let cache_dir = dirs::cache_dir()
            .ok_or("Could not find cache directory")?
            .join("bob");

        std::fs::create_dir_all(&cache_dir)?;

        let response = reqwest::get(BUN_DOWNLOAD_URL).await?;
        let bytes = response.bytes().await?;

        let cursor = std::io::Cursor::new(bytes);
        let mut archive = zip::ZipArchive::new(cursor)?;

        let bun_name = if cfg!(windows) { "bun.exe" } else { "bun" };

        for i in 0..archive.len() {
            let mut file = archive.by_index(i)?;
            let file_name = file.name().to_string();

            if file_name.ends_with(bun_name) {
                let out_path = cache_dir.join(bun_name);
                let mut outfile = std::fs::File::create(&out_path)?;
                std::io::copy(&mut file, &mut outfile)?;

                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    std::fs::set_permissions(&out_path, std::fs::Permissions::from_mode(0o755))?;
                }

                return Ok(out_path);
            }
        }

        Err("Bun executable not found in archive".into())
    }

    // ------------------------------------------------------------------------
    // Configuration Management
    // ------------------------------------------------------------------------

    /// Saves the current project list to persistent storage
    fn save_config(&self) {
        let config = Config {
            projects: self.projects.clone(),
        };
        let _ = confy::store("bob", "config", config);
    }

    /// Checks if a project has any running tasks
    fn has_running_tasks(&self, proj_idx: usize) -> bool {
        self.processes.keys().any(|(p_idx, _)| *p_idx == proj_idx)
    }

    /// Refreshes project visibility based on package.json existence
    fn refresh_project_visibility(&mut self) {
        for project in &mut self.projects {
            let package_json = Path::new(&project.path).join("package.json");
            project.hidden = !package_json.exists();
        }
    }

    /// Refreshes tasks for a specific project
    fn refresh_project_tasks(&mut self, project_path: &Path) {
        let project_path_str = project_path.to_string_lossy();

        for project in self.projects.iter_mut() {
            if project.path == project_path_str {
                let package_json = project_path.join("package.json");

                if let Ok(content) = std::fs::read_to_string(&package_json) {
                    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                        if let Some(scripts) = parsed["scripts"].as_object() {
                            // Preserve running state and logs for existing tasks
                            let mut existing_tasks: HashMap<String, (bool, Vec<String>)> = project
                                .tasks
                                .iter()
                                .map(|t| (t.name.clone(), (t.running, t.logs.clone())))
                                .collect();

                            project.tasks = scripts
                                .keys()
                                .map(|name| {
                                    let (was_running, logs) = existing_tasks
                                        .remove(name)
                                        .unwrap_or_else(|| (false, vec![format!("[INFO] Task '{}' ready", name)]));

                                    ProjectTask {
                                        name: name.clone(),
                                        running: was_running,
                                        logs,
                                        failed: false,
                                    }
                                })
                                .collect();
                        }

                        project.hidden = false;
                    }
                }

                break;
            }
        }

        self.save_config();
    }

    // ------------------------------------------------------------------------
    // UI Components
    // ------------------------------------------------------------------------

    /// Creates a flat icon button with consistent styling
    fn flat_icon_button(icon: &str, icon_size: u16, message: Message) -> iced::widget::Button<'_, Message> {
        button(
            text(icon)
                .size(icon_size)
                .font(BOOTSTRAP_FONT)
                .color(TEXT_PRIMARY)
        )
        .width(Length::Fill)
        .style(|_theme: &_, status| {
            let background = match status {
                button::Status::Hovered => BG_HOVER,
                button::Status::Pressed => BG_SECONDARY,
                _ => BG_SECONDARY,
            };

            button::Style {
                background: Some(background.into()),
                text_color: TEXT_PRIMARY,
                border: iced::Border {
                    color: BORDER_COLOR,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                ..Default::default()
            }
        })
        .on_press(message)
    }

    /// Renders a single task row with play/pause control
    fn task_row<'a>(
        &self,
        task: &'a ProjectTask,
        proj_idx: usize,
        task_idx: usize,
        is_selected: bool,
    ) -> Element<'a, Message> {
        let (icon, message) = if task.running {
            (ICON_PAUSE, Some(Message::StopTask(proj_idx, task_idx)))
        } else {
            (ICON_PLAY, Some(Message::StartTask(proj_idx, task_idx)))
        };

        let task_text = text(&task.name).color(if task.failed { TEXT_ERROR } else { TEXT_PRIMARY });

        let play_pause_icon: Element<'a, Message> = if let Some(msg) = message {
            mouse_area(
                text(icon)
                    .size(14)
                    .font(BOOTSTRAP_FONT)
                    .color(TEXT_PRIMARY)
            )
            .on_press(msg)
            .into()
        } else {
            text(icon)
                .size(14)
                .font(BOOTSTRAP_FONT)
                .color(Color::from_rgb(0.5, 0.5, 0.5))
                .into()
        };

        mouse_area(
            container(
                row![task_text, Space::with_width(Length::Fill), play_pause_icon]
                    .spacing(5)
                    .align_y(iced::Alignment::Center)
            )
            .padding([5.0, 20.0])
            .width(Length::Fill)
            .style(move |_theme: &_| container::Style {
                background: Some(if is_selected { BG_SELECTED } else { BG_PRIMARY }.into()),
                ..Default::default()
            })
        )
        .on_press(Message::SelectTask(proj_idx, task_idx))
        .into()
    }

    /// Renders a project section with title and task list
    fn project_section<'a>(
        &self,
        project: &'a Project,
        proj_idx: usize,
        is_dragging: bool,
        selected_task: Option<(usize, usize)>,
    ) -> Element<'a, Message> {
        let has_running = self.has_running_tasks(proj_idx);

        let remove_button: Element<'a, Message> = if has_running {
            // Show disabled trash icon
            text(ICON_TRASH)
                .size(12)
                .font(BOOTSTRAP_FONT)
                .color(Color::from_rgb(0.3, 0.3, 0.3))
                .into()
        } else {
            mouse_area(
                text(ICON_TRASH)
                    .size(12)
                    .font(BOOTSTRAP_FONT)
                    .color(TEXT_ERROR)
            )
            .on_press(Message::RemoveProject(proj_idx))
            .into()
        };

        let project_title = mouse_area(
            container(
                row![
                    text(&project.name)
                        .size(16)
                        .color(TEXT_PRIMARY)
                        .font(iced::Font {
                            weight: iced::font::Weight::Bold,
                            ..Default::default()
                        }),
                    Space::with_width(Length::Fill),
                    remove_button
                ]
                .spacing(5)
                .align_y(iced::Alignment::Center)
            )
            .padding(5)
            .width(Length::Fill)
            .style(move |_theme: &_| container::Style {
                background: Some(if is_dragging { BG_DRAGGING } else { BG_PRIMARY }.into()),
                ..Default::default()
            })
        )
        .on_press(Message::ProjectDragStart(proj_idx))
        .on_enter(Message::ProjectHovered(proj_idx));

        let mut project_column = column![project_title].spacing(5);

        for (task_idx, task) in project.tasks.iter().enumerate() {
            let is_selected = selected_task == Some((proj_idx, task_idx));
            project_column = project_column.push(self.task_row(task, proj_idx, task_idx, is_selected));
        }

        project_column.into()
    }

    /// Renders the left sidebar with projects and tasks
    fn left_pane(&self) -> Element<'_, Message> {
        let button_row = row![
            Self::flat_icon_button(ICON_PLUS, 20, Message::CreateProject),
            Self::flat_icon_button(ICON_FOLDER, 18, Message::ImportProject),
        ]
        .spacing(5);

        let mut content = column![button_row].spacing(10).padding(10);

        for (proj_idx, project) in self.projects.iter().enumerate() {
            if !project.hidden {
                let is_dragging = self.dragging_project == Some(proj_idx);
                content = content.push(self.project_section(
                    project,
                    proj_idx,
                    is_dragging,
                    self.selected_task,
                ));
            }
        }

        // Wrap in mouse_area to capture release events globally
        mouse_area(
            container(scrollable(content))
                .width(Length::Fixed(self.left_panel_width))
                .height(Length::Fill)
                .style(|_theme: &_| container::Style {
                    background: Some(BG_PRIMARY.into()),
                    ..Default::default()
                })
        )
        .on_release(Message::ProjectDragEnd)
        .into()
    }

    /// Renders a draggable divider for resizing panels
    fn divider(&self) -> Element<'_, Message> {
        let divider_color = if self.dragging_divider {
            Color::from_rgb(0.0, 0.5, 1.0)
        } else {
            BORDER_COLOR
        };

        mouse_area(
            container(Space::with_width(Length::Fixed(0.0)))
                .width(Length::Fixed(4.0))
                .height(Length::Fill)
                .style(move |_theme: &_| container::Style {
                    background: Some(divider_color.into()),
                    ..Default::default()
                })
        )
        .on_press(Message::DividerDragStart)
        .into()
    }

    /// Renders the central pane with task logs
    fn central_pane(&self) -> Element<'_, Message> {
        let content = if let Some((proj_idx, task_idx)) = self.selected_task {
            if let Some(project) = self.projects.get(proj_idx) {
                if let Some(task) = project.tasks.get(task_idx) {
                    let header = container(
                        text(format!("{} - {}", project.name, task.name))
                            .size(18)
                            .color(TEXT_PRIMARY)
                            .font(iced::Font {
                                weight: iced::font::Weight::Bold,
                                ..Default::default()
                            })
                    )
                    .padding(15)
                    .width(Length::Fill)
                    .style(|_theme: &_| container::Style {
                        background: Some(BG_SECONDARY.into()),
                        border: iced::Border {
                            color: BORDER_COLOR,
                            width: 1.0,
                            radius: 0.0.into(),
                        },
                        ..Default::default()
                    });

                    let mut logs_content = column![].spacing(3);
                    for log in &task.logs {
                        logs_content = logs_content.push(
                            text(log)
                                .size(13)
                                .color(TEXT_PRIMARY)
                                .font(iced::Font {
                                    family: iced::font::Family::Monospace,
                                    ..Default::default()
                                })
                        );
                    }

                    let logs_scroll = scrollable(
                        container(logs_content)
                            .padding(15)
                            .width(Length::Fill)
                    )
                    .height(Length::Fill);

                    return container(column![header, logs_scroll])
                        .width(Length::Fill)
                        .height(Length::Fill)
                        .style(|_theme: &_| container::Style {
                            background: Some(BG_PRIMARY.into()),
                            ..Default::default()
                        })
                        .into();
                }
            }
            text("Task not found").color(TEXT_PRIMARY)
        } else {
            text("Select a task to view logs")
                .size(14)
                .color(Color::from_rgb(0.5, 0.5, 0.5))
        };

        container(
            container(content)
                .padding(15)
                .center_x(Length::Fill)
                .center_y(Length::Fill)
        )
        .width(Length::Fill)
        .height(Length::Fill)
        .style(|_theme: &_| container::Style {
            background: Some(BG_PRIMARY.into()),
            ..Default::default()
        })
        .into()
    }

    // ------------------------------------------------------------------------
    // Message Handlers
    // ------------------------------------------------------------------------

    /// Handles project import logic
    fn handle_import(&mut self, path: PathBuf) {
        if path.file_name().and_then(|n| n.to_str()) != Some("package.json") {
            return;
        }

        let Ok(content) = std::fs::read_to_string(&path) else { return };
        let Ok(package_json) = serde_json::from_str::<serde_json::Value>(&content) else { return };

        let project_name = package_json["name"]
            .as_str()
            .unwrap_or("Unknown Project")
            .to_string();

        let project_path = path
            .parent()
            .unwrap_or(std::path::Path::new(""))
            .to_string_lossy()
            .to_string();

        let tasks = package_json["scripts"]
            .as_object()
            .map(|scripts| {
                scripts
                    .keys()
                    .map(|name| ProjectTask {
                        name: name.clone(),
                        running: false,
                        logs: vec![format!("[INFO] Task '{}' ready", name)],
                        failed: false,
                    })
                    .collect()
            })
            .unwrap_or_default();

        self.projects.push(Project {
            name: project_name,
            path: project_path,
            tasks,
            hidden: false,
        });

        self.save_config();
    }

    /// Updates selected task indices after drag-and-drop reordering
    fn update_selected_after_reorder(&mut self, from: usize, to: usize) {
        if let Some((selected_proj, task_idx)) = self.selected_task {
            self.selected_task = Some((
                match selected_proj {
                    idx if idx == from => to,
                    idx if from < to && idx > from && idx <= to => idx - 1,
                    idx if from > to && idx >= to && idx < from => idx + 1,
                    idx => idx,
                },
                task_idx,
            ));
        }
    }

    /// Starts a task process with real-time output streaming
    fn start_task_process(&mut self, proj_idx: usize, task_idx: usize) -> IcedTask<Message> {
        if self.bun_path.is_none() {
            if !self.bun_downloading {
                self.bun_downloading = true;
                return IcedTask::perform(Self::download_bun(), |result| {
                    match result {
                        Ok(_) => Message::BunReady,
                        Err(e) => {
                            eprintln!("Failed to download bun: {}", e);
                            Message::BunReady
                        }
                    }
                });
            }
            return IcedTask::none();
        }

        let Some(project) = self.projects.get_mut(proj_idx) else { return IcedTask::none() };
        let Some(task) = project.tasks.get_mut(task_idx) else { return IcedTask::none() };

        task.running = true;
        task.logs.clear();
        task.logs.push(format!("[INFO] Starting task '{}'...", task.name));

        let bun_path = self.bun_path.clone().unwrap();
        let project_path = PathBuf::from(&project.path);
        let task_name = task.name.clone();

        // Spawn the process and set up output streaming
        let output_handle = tokio::spawn(async move {
            let mut output_lines = Vec::new();

            // Step 1: Run bun install first
            output_lines.push("[INFO] Running bun install...".to_string());

            let install_result = Command::new(&bun_path)
                .arg("install")
                .current_dir(&project_path)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn();

            match install_result {
                Ok(mut install_child) => {
                    let install_stdout = install_child.stdout.take();
                    let install_stderr = install_child.stderr.take();

                    // Capture install stdout
                    let install_stdout_task = if let Some(stdout) = install_stdout {
                        Some(tokio::spawn(async move {
                            let reader = BufReader::new(stdout);
                            let mut lines = reader.lines();
                            let mut captured = Vec::new();
                            while let Ok(Some(line)) = lines.next_line().await {
                                captured.push(line);
                            }
                            captured
                        }))
                    } else {
                        None
                    };

                    // Capture install stderr
                    let install_stderr_task = if let Some(stderr) = install_stderr {
                        Some(tokio::spawn(async move {
                            let reader = BufReader::new(stderr);
                            let mut lines = reader.lines();
                            let mut captured = Vec::new();
                            while let Ok(Some(line)) = lines.next_line().await {
                                captured.push(line);
                            }
                            captured
                        }))
                    } else {
                        None
                    };

                    // Wait for install to complete
                    let install_status = install_child.wait().await;

                    // Collect install output
                    if let Some(task) = install_stdout_task {
                        if let Ok(lines) = task.await {
                            output_lines.extend(lines);
                        }
                    }

                    if let Some(task) = install_stderr_task {
                        if let Ok(lines) = task.await {
                            output_lines.extend(lines);
                        }
                    }

                    let install_success = install_status.map(|s| s.success()).unwrap_or(false);
                    if install_success {
                        output_lines.push("[INFO] Dependencies installed successfully".to_string());
                    } else {
                        output_lines.push("[WARN] bun install completed with errors, continuing anyway...".to_string());
                    }
                }
                Err(e) => {
                    output_lines.push(format!("[WARN] Failed to run bun install: {}", e));
                }
            }

            // Step 2: Run the actual task
            output_lines.push(format!("[INFO] Running task '{}'...", task_name));

            let mut child = match Command::new(&bun_path)
                .arg("run")
                .arg(&task_name)
                .current_dir(&project_path)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
            {
                Ok(child) => child,
                Err(e) => {
                    eprintln!("Failed to start process: {}", e);
                    output_lines.push(format!("[ERROR] Failed to start: {}", e));
                    return (proj_idx, task_idx, false, output_lines);
                }
            };

            let stdout = child.stdout.take();
            let stderr = child.stderr.take();

            // Capture stdout
            let stdout_task = if let Some(stdout) = stdout {
                Some(tokio::spawn(async move {
                    let reader = BufReader::new(stdout);
                    let mut lines = reader.lines();
                    let mut captured = Vec::new();
                    while let Ok(Some(line)) = lines.next_line().await {
                        captured.push(line);
                    }
                    captured
                }))
            } else {
                None
            };

            // Capture stderr
            let stderr_task = if let Some(stderr) = stderr {
                Some(tokio::spawn(async move {
                    let reader = BufReader::new(stderr);
                    let mut lines = reader.lines();
                    let mut captured = Vec::new();
                    while let Ok(Some(line)) = lines.next_line().await {
                        captured.push(format!("[STDERR] {}", line));
                    }
                    captured
                }))
            } else {
                None
            };

            // Wait for completion
            let status = child.wait().await;

            // Collect all output
            if let Some(task) = stdout_task {
                if let Ok(lines) = task.await {
                    output_lines.extend(lines);
                }
            }

            if let Some(task) = stderr_task {
                if let Ok(lines) = task.await {
                    output_lines.extend(lines);
                }
            }

            let success = status.map(|s| s.success()).unwrap_or(false);

            (proj_idx, task_idx, success, output_lines)
        });

        IcedTask::perform(
            async move {
                output_handle.await.unwrap()
            },
            |(proj_idx, task_idx, success, output_lines)| {
                Message::TaskCompleted(proj_idx, task_idx, success, output_lines)
            },
        )
    }

    /// Stops a running task
    fn stop_task_process(&mut self, proj_idx: usize, task_idx: usize) -> IcedTask<Message> {
        if let Some(handle) = self.processes.remove(&(proj_idx, task_idx)) {
            if let Some(project) = self.projects.get_mut(proj_idx) {
                if let Some(task) = project.tasks.get_mut(task_idx) {
                    task.running = false;
                    task.logs.push(format!("[INFO] Task '{}' stopped", task.name));
                }
            }

            return IcedTask::perform(
                async move {
                    let mut child = handle.child.lock().await;
                    let _ = child.kill().await;
                },
                |_| Message::RefreshProjects,
            );
        }

        IcedTask::none()
    }

    /// Main message update handler
    fn update(&mut self, message: Message) -> IcedTask<Message> {
        match message {
            Message::ImportProject => {
                return IcedTask::perform(
                    async {
                        rfd::AsyncFileDialog::new()
                            .set_title("Select package.json")
                            .add_filter("package.json", &["json"])
                            .pick_file()
                            .await
                            .map(|handle| handle.path().to_path_buf())
                    },
                    Message::ImportProjectSelected,
                );
            }

            Message::ImportProjectSelected(Some(path)) => self.handle_import(path),
            Message::ImportProjectSelected(None) => {}

            Message::CreateProject => {
                let new_project_idx = self.projects.len();
                self.projects.push(Project {
                    name: format!("New Project {}", new_project_idx + 1),
                    path: String::new(),
                    tasks: vec![ProjectTask {
                        name: "Task 1".to_string(),
                        running: false,
                        logs: vec!["[INFO] Task created".to_string()],
                        failed: false,
                    }],
                    hidden: true, // Hidden until package.json exists
                });
                self.selected_task = Some((new_project_idx, 0));
                self.save_config();
            }

            Message::RemoveProject(idx) => {
                if idx < self.projects.len() && !self.has_running_tasks(idx) {
                    self.projects.remove(idx);

                    if let Some((selected_proj, task_idx)) = self.selected_task {
                        self.selected_task = match selected_proj {
                            proj if proj == idx => None,
                            proj if proj > idx => Some((proj - 1, task_idx)),
                            _ => self.selected_task,
                        };
                    }

                    self.save_config();
                }
            }

            Message::SelectTask(project_idx, task_idx) => {
                self.selected_task = Some((project_idx, task_idx));
            }

            Message::StartTask(proj_idx, task_idx) => {
                return self.start_task_process(proj_idx, task_idx);
            }

            Message::StopTask(proj_idx, task_idx) => {
                return self.stop_task_process(proj_idx, task_idx);
            }

            Message::TaskOutput(proj_idx, task_idx, line) => {
                if let Some(project) = self.projects.get_mut(proj_idx) {
                    if let Some(task) = project.tasks.get_mut(task_idx) {
                        task.logs.push(line);
                    }
                }
            }

            Message::TaskCompleted(proj_idx, task_idx, success, output_lines) => {
                self.processes.remove(&(proj_idx, task_idx));

                if let Some(project) = self.projects.get_mut(proj_idx) {
                    if let Some(task) = project.tasks.get_mut(task_idx) {
                        task.running = false;
                        task.failed = !success;

                        // Add all captured output to logs
                        task.logs.extend(output_lines);

                        let status = if success { "completed successfully" } else { "failed" };
                        task.logs.push(format!("[INFO] Task '{}' {}", task.name, status));
                    }
                }
            }

            Message::ProjectDragStart(idx) => {
                self.dragging_project = Some(idx);
            }

            Message::ProjectDragEnd => {
                self.dragging_project = None;
            }

            Message::ProjectHovered(to_idx) => {
                if let Some(from_idx) = self.dragging_project {
                    if from_idx != to_idx
                        && from_idx < self.projects.len()
                        && to_idx < self.projects.len()
                    {
                        let project = self.projects.remove(from_idx);
                        self.projects.insert(to_idx, project);

                        self.update_selected_after_reorder(from_idx, to_idx);
                        self.dragging_project = Some(to_idx);
                        self.save_config();
                    }
                }
            }

            Message::DividerDragStart => {
                self.dragging_divider = true;
            }

            Message::DividerDragging(x) => {
                if self.dragging_divider {
                    self.left_panel_width = x.max(200.0).min(800.0);
                }
            }

            Message::DividerDragEnd => {
                self.dragging_divider = false;
            }

            Message::BunReady => {
                self.bun_path = Self::get_bun_path();
                self.bun_downloading = false;
            }

            Message::BunDownloadProgress(_progress) => {
                // Update download progress UI if needed
            }

            Message::FileChanged(path) => {
                if path.file_name().and_then(|n| n.to_str()) == Some("package.json") {
                    if let Some(parent) = path.parent() {
                        self.refresh_project_tasks(parent);
                    }
                }
                self.refresh_project_visibility();
            }

            Message::RefreshProjects => {
                self.refresh_project_visibility();
            }
        }

        IcedTask::none()
    }

    /// Subscription for file watching
    fn subscription(&self) -> Subscription<Message> {
        file_watcher_subscription(self.projects.clone())
    }

    /// Main view rendering
    fn view(&self) -> Element<'_, Message> {
        row![self.left_pane(), self.divider(), self.central_pane()].into()
    }
}
