export async function playTreeMutation({ treeScene, emit, payload = {} }) {
  const mutation = payload.mutation ?? {};
  const snapshot = payload.snapshot ?? {};
  const chapters = snapshot.chapters ?? [];
  emit('tree.mutationStarted', { type: mutation.type, id: mutation.nodeId });
  const agePromise = treeScene.setAge(snapshot.treeAge, {
    animate: mutation.structuralAgeChanged,
  });
  if (mutation.structuralAgeChanged) {
    await treeScene.waitForGrowthLead(0.08);
  }

  if (mutation.type === 'addChapter') {
    const chapter = chapters.find((item) => item.id === mutation.nodeId);
    if (chapter) {
      emit('tree.branchGrowthStarted', { kind: 'chapter', id: chapter.id });
      await Promise.all([agePromise, treeScene.growChapter(chapter)]);
    }
  } else if (mutation.type === 'addSection') {
    const chapter = chapters.find((item) => item.id === mutation.parentId);
    const section = chapter?.sections?.find((item) => item.id === mutation.nodeId);
    if (section) {
      emit('tree.branchGrowthStarted', { kind: 'section', id: section.id });
      await Promise.all([
        agePromise,
        treeScene.growSection({ ...section, chapterId: chapter.id }),
      ]);
    }
  } else if (mutation.type === 'removeChapter') {
    emit('tree.branchRetractionStarted', { kind: 'chapter', id: mutation.nodeId });
    await Promise.all([agePromise, treeScene.removeChapter(mutation.nodeId)]);
  } else if (mutation.type === 'removeSection') {
    emit('tree.branchRetractionStarted', { kind: 'section', id: mutation.nodeId });
    await Promise.all([agePromise, treeScene.removeSection(mutation.nodeId)]);
  } else {
    await agePromise;
  }

  await treeScene.setAge(snapshot.treeAge, { animate: false });
  await treeScene.sync(snapshot);
  emit('tree.mutationCompleted', { type: mutation.type, id: mutation.nodeId });
}
