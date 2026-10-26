import 'package:opennutritracker/features/gym/domain/gym_models.dart';

/// The built-in exercise library, seeded into storage on first use. One line
/// per exercise: `name|muscle|equipment[|b]`, where a trailing `b` marks a
/// bodyweight exercise (reps, with optional added weight).
///
/// Ids are stable (`seed_<n>`), so renaming an entry here doesn't detach the
/// history logged against it.
const _lines = <String>[
  'Barbell Bench Press|chest|Barbell',
  'Incline Barbell Bench Press|chest|Barbell',
  'Dumbbell Bench Press|chest|Dumbbell',
  'Incline Dumbbell Press|chest|Dumbbell',
  'Machine Chest Press|chest|Machine',
  'Cable Fly|chest|Cable',
  'Dumbbell Fly|chest|Dumbbell',
  'Pec Deck|chest|Machine',
  'Push-up|chest|Bodyweight|b',
  'Chest Dip|chest|Bodyweight|b',
  'Deadlift|back|Barbell',
  'Barbell Row|back|Barbell',
  'Dumbbell Row|back|Dumbbell',
  'Seated Cable Row|back|Cable',
  'T-Bar Row|back|Machine',
  'Lat Pulldown|back|Cable',
  'Pull-up|back|Bodyweight|b',
  'Chin-up|back|Bodyweight|b',
  'Straight-Arm Pulldown|back|Cable',
  'Back Extension|back|Bodyweight|b',
  'Overhead Press|shoulders|Barbell',
  'Seated Dumbbell Press|shoulders|Dumbbell',
  'Machine Shoulder Press|shoulders|Machine',
  'Arnold Press|shoulders|Dumbbell',
  'Lateral Raise|shoulders|Dumbbell',
  'Cable Lateral Raise|shoulders|Cable',
  'Front Raise|shoulders|Dumbbell',
  'Rear Delt Fly|shoulders|Dumbbell',
  'Face Pull|shoulders|Cable',
  'Barbell Shrug|shoulders|Barbell',
  'Barbell Curl|biceps|Barbell',
  'EZ-Bar Curl|biceps|Barbell',
  'Dumbbell Curl|biceps|Dumbbell',
  'Hammer Curl|biceps|Dumbbell',
  'Incline Dumbbell Curl|biceps|Dumbbell',
  'Preacher Curl|biceps|Machine',
  'Cable Curl|biceps|Cable',
  'Triceps Pushdown|triceps|Cable',
  'Overhead Triceps Extension|triceps|Dumbbell',
  'Skull Crusher|triceps|Barbell',
  'Close-Grip Bench Press|triceps|Barbell',
  'Triceps Dip|triceps|Bodyweight|b',
  'Bench Dip|triceps|Bodyweight|b',
  'Wrist Curl|forearms|Dumbbell',
  'Reverse Curl|forearms|Barbell',
  'Farmer\'s Carry|forearms|Dumbbell',
  'Back Squat|quads|Barbell',
  'Front Squat|quads|Barbell',
  'Leg Press|quads|Machine',
  'Hack Squat|quads|Machine',
  'Goblet Squat|quads|Dumbbell',
  'Bulgarian Split Squat|quads|Dumbbell',
  'Walking Lunge|quads|Dumbbell',
  'Leg Extension|quads|Machine',
  'Bodyweight Squat|quads|Bodyweight|b',
  'Romanian Deadlift|hamstrings|Barbell',
  'Stiff-Leg Deadlift|hamstrings|Barbell',
  'Lying Leg Curl|hamstrings|Machine',
  'Seated Leg Curl|hamstrings|Machine',
  'Good Morning|hamstrings|Barbell',
  'Hip Thrust|glutes|Barbell',
  'Glute Bridge|glutes|Bodyweight|b',
  'Cable Kickback|glutes|Cable',
  'Hip Abduction|glutes|Machine',
  'Step-up|glutes|Dumbbell',
  'Standing Calf Raise|calves|Machine',
  'Seated Calf Raise|calves|Machine',
  'Donkey Calf Raise|calves|Bodyweight|b',
  'Crunch|abs|Bodyweight|b',
  'Sit-up|abs|Bodyweight|b',
  'Hanging Leg Raise|abs|Bodyweight|b',
  'Cable Crunch|abs|Cable',
  'Ab Wheel Rollout|abs|Bodyweight|b',
  'Russian Twist|abs|Bodyweight|b',
  'Plank (reps = seconds)|abs|Bodyweight|b',
  'Clean and Press|fullBody|Barbell',
  'Kettlebell Swing|fullBody|Kettlebell',
  'Burpee|fullBody|Bodyweight|b',
  'Thruster|fullBody|Barbell',
];

List<Exercise> buildSeedExercises() {
  final exercises = <Exercise>[];
  for (var i = 0; i < _lines.length; i++) {
    final parts = _lines[i].split('|');
    exercises.add(
      Exercise(
        id: 'seed_$i',
        name: parts[0],
        muscle: MuscleGroup.fromName(parts[1]),
        equipment: parts[2],
        kind: parts.length > 3 ? ExerciseKind.bodyweight : ExerciseKind.weighted,
      ),
    );
  }
  return exercises;
}
