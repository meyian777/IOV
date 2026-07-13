use std::env;
use std::process::ExitCode;

struct Policy {
    name: &'static str,
    description: &'static str,
    risk: &'static str,
    requires_confirmation: bool,
}

fn policy_for(action: &str) -> Option<Policy> {
    match action {
        "LIST_FILES" => Some(Policy {
            name: "LIST_FILES",
            description: "Read the names of files in the active project.",
            risk: "read_only",
            requires_confirmation: false,
        }),
        "OPEN_VSCODE" => Some(Policy {
            name: "OPEN_VSCODE",
            description: "Open Visual Studio Code on this computer.",
            risk: "routine_system",
            requires_confirmation: false,
        }),
        "OPEN_PROJECT" => Some(Policy {
            name: "OPEN_PROJECT",
            description: "Open the active project in Visual Studio Code.",
            risk: "routine_system",
            requires_confirmation: false,
        }),
        "OPEN_TERMINAL" => Some(Policy {
            name: "OPEN_TERMINAL",
            description: "Open the Terminal application.",
            risk: "routine_system",
            requires_confirmation: false,
        }),
        "RUN_FLUTTER" => Some(Policy {
            name: "RUN_FLUTTER",
            description: "Start the Flutter application in Chrome.",
            risk: "process_execution",
            requires_confirmation: true,
        }),
        "RUN_PYTHON_SCRIPT" => Some(Policy {
            name: "RUN_PYTHON_SCRIPT",
            description: "Execute a Python script inside the active project.",
            risk: "process_execution",
            requires_confirmation: true,
        }),
        _ => None,
    }
}

fn escape_json(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
}

fn policy_json(policy: Policy) -> String {
    format!(
        concat!(
            "{{\"success\":true,\"known\":true,",
            "\"name\":\"{}\",\"description\":\"{}\",",
            "\"risk\":\"{}\",\"requires_confirmation\":{}}}"
        ),
        escape_json(policy.name),
        escape_json(policy.description),
        escape_json(policy.risk),
        policy.requires_confirmation,
    )
}

fn main() -> ExitCode {
    let arguments: Vec<String> = env::args().collect();
    match arguments.get(1).map(String::as_str) {
        Some("health") => {
            println!(
                "{{\"success\":true,\"service\":\"labvoice-native-core\",\
                 \"version\":\"{}\",\"language\":\"rust\"}}",
                env!("CARGO_PKG_VERSION")
            );
            ExitCode::SUCCESS
        }
        Some("policy") => {
            let Some(action) = arguments.get(2) else {
                eprintln!("missing action");
                return ExitCode::from(2);
            };
            match policy_for(action) {
                Some(policy) => {
                    println!("{}", policy_json(policy));
                    ExitCode::SUCCESS
                }
                None => {
                    println!(
                        "{{\"success\":false,\"known\":false,\
                         \"error\":\"unknown_action\"}}"
                    );
                    ExitCode::from(3)
                }
            }
        }
        _ => {
            eprintln!("usage: labvoice-native-core <health|policy ACTION>");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_only_policy_does_not_require_confirmation() {
        let policy = policy_for("LIST_FILES").unwrap();
        assert_eq!(policy.risk, "read_only");
        assert!(!policy.requires_confirmation);
    }

    #[test]
    fn routine_system_policy_does_not_require_confirmation() {
        let policy = policy_for("OPEN_TERMINAL").unwrap();
        assert_eq!(policy.risk, "routine_system");
        assert!(!policy.requires_confirmation);
    }

    #[test]
    fn python_execution_policy_requires_confirmation() {
        let policy = policy_for("RUN_PYTHON_SCRIPT").unwrap();
        assert_eq!(policy.risk, "process_execution");
        assert!(policy.requires_confirmation);
    }

    #[test]
    fn unknown_actions_are_rejected() {
        assert!(policy_for("DELETE_EVERYTHING").is_none());
    }
}
